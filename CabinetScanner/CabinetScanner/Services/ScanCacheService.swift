import Foundation
import SwiftData

/// Actor that owns the offline scan cache. Validates scans in O(1) against
/// in-memory mirrors of the registry and packed panels, and persists the
/// authoritative copy to SwiftData so the cache survives app restarts.
///
/// All public APIs are async and isolated to the actor — safe to call from
/// any context (ViewModels, Services).
actor ScanCacheService {
    static let shared = ScanCacheService()

    enum ValidationResult: Equatable {
        case ok(panelUid: String, cabinetName: String, partNumber: String)
        case notInRegistry
        case alreadyPacked(boxId: String)
        case registryNotCached
    }

    private let container: ModelContainer
    private let api: APIServiceProtocol

    // In-memory mirrors, rebuilt lazily from SwiftData.
    // Keyed by manifestId → (panelUid → CachedPanelRegistry)
    private var registryByManifest: [String: [String: CachedRegistryEntry]] = [:]
    // Keyed by consignmentId → (panelUid → boxId)
    private var packedByConsignment: [String: [String: String]] = [:]
    private var registryWarmed: Set<String> = []   // "manifestId|projectName"
    private var packedWarmed: Set<String> = []

    private struct CachedRegistryEntry {
        let panelUid: String
        let cabinetName: String
        let partNumber: String
        let lengthMm: Int
        let widthMm: Int
        let thicknessMm: Int
        let material: String
    }

    /// One persistent ModelContext owned by this actor. Reused across all
    /// SwiftData reads/writes — creating a fresh `ModelContext(container)`
    /// per call had measurable overhead on the scan hot path because each
    /// new context re-initialises pending-changes tracking and re-resolves
    /// the schema. Actor isolation makes this safe to share.
    private let context: ModelContext

    init(
        container: ModelContainer = ScanCacheContainer.shared,
        api: APIServiceProtocol = ServiceContainer.shared.api
    ) {
        self.container = container
        self.api = api
        self.context = ModelContext(container)
    }

    // MARK: - Registry

    /// Pre-load the registry for a (manifestId, projectName) pair.
    /// - Honours server `notModified` to avoid wasted work.
    /// - On network failure, falls back silently to whatever is on disk.
    func loadRegistry(manifestId: String, projectName: String, force: Bool = false) async {
        let key = "\(manifestId)|\(projectName)"
        let existingMeta = fetchMeta(manifestId: manifestId, projectName: projectName)
        let etag = (force ? nil : existingMeta?.etag)

        do {
            let response = try await api.fetchPanelRegistry(
                manifestId: manifestId,
                projectName: projectName,
                etag: etag
            )
            if response.notModified == true, existingMeta != nil {
                // Make sure the in-memory mirror is warmed from disk.
                warmRegistryFromDisk(manifestId: manifestId, projectName: projectName)
                registryWarmed.insert(key)
                return
            }

            try await persistRegistry(
                manifestId: manifestId,
                projectName: projectName,
                etag: response.etag,
                panels: response.panels
            )
            warmRegistryFromDisk(manifestId: manifestId, projectName: projectName)
            registryWarmed.insert(key)
        } catch {
            // Fall back to cached data if we have any.
            warmRegistryFromDisk(manifestId: manifestId, projectName: projectName)
            if !registryByManifest[manifestId, default: [:]].isEmpty {
                registryWarmed.insert(key)
            }
        }
    }

    // MARK: - Packed-panel mirror

    /// Refresh "what's already been packed in this consignment" from the server.
    /// On failure, fall back to whatever is on disk.
    func loadPackedPanels(consignmentId: String) async {
        do {
            let response = try await api.fetchPackedPanels(consignmentId: consignmentId)
            try await persistPackedPanels(
                consignmentId: consignmentId,
                panels: response.panels
            )
            warmPackedFromDisk(consignmentId: consignmentId)
            packedWarmed.insert(consignmentId)
        } catch {
            warmPackedFromDisk(consignmentId: consignmentId)
            if !packedByConsignment[consignmentId, default: [:]].isEmpty {
                packedWarmed.insert(consignmentId)
            }
        }
    }

    // MARK: - Validation (the hot path)

    func validate(
        boxId _: String,
        manifestId: String,
        consignmentId: String,
        triplet: ScanTriplet
    ) -> ValidationResult {
        let panelUid = "\(triplet.projectName)|\(triplet.cabinetName)|\(triplet.partNumber)"
        let registryKey = "\(manifestId)|\(triplet.projectName)"

        // Cold-offline gate: if we have no registry meta for this manifest+project,
        // we can't safely accept scans.
        if !registryWarmed.contains(registryKey) {
            warmRegistryFromDisk(manifestId: manifestId, projectName: triplet.projectName)
            if fetchMeta(manifestId: manifestId, projectName: triplet.projectName) == nil {
                return .registryNotCached
            }
            registryWarmed.insert(registryKey)
        }

        let registry = registryByManifest[manifestId] ?? [:]
        guard let entry = registry[panelUid] else {
            return .notInRegistry
        }

        // Lazy-warm the packed mirror if needed.
        if !packedWarmed.contains(consignmentId) {
            warmPackedFromDisk(consignmentId: consignmentId)
            packedWarmed.insert(consignmentId)
        }

        if let existingBoxId = packedByConsignment[consignmentId]?[panelUid] {
            return .alreadyPacked(boxId: existingBoxId)
        }

        return .ok(panelUid: entry.panelUid, cabinetName: entry.cabinetName, partNumber: entry.partNumber)
    }

    // MARK: - Local optimistic write

    /// Record a successful local scan: persist the PendingScan and add it to
    /// the optimistic packed mirror so subsequent dup-detection works.
    func recordLocalScan(_ pending: PendingScan) {
        context.insert(pending)
        // Also write a PackedPanelMirror row keyed by (consignmentId, panelUid).
        // SwiftData will treat this as the "we believe this is packed" state.
        let mirror = PackedPanelMirror(
            consignmentId: pending.consignmentId,
            panelUid: pending.panelUid,
            boxId: pending.boxId,
            syncedAt: .now
        )
        context.insert(mirror)
        do {
            try context.save()
        } catch {
            // SwiftData unique-constraint conflicts are non-fatal here — the
            // mirror already shows it as packed. Log for diagnostics.
            print("[ScanCacheService.recordLocalScan] save error: \(error)")
        }

        // Update in-memory mirror.
        var mapForCons = packedByConsignment[pending.consignmentId] ?? [:]
        mapForCons[pending.panelUid] = pending.boxId
        packedByConsignment[pending.consignmentId] = mapForCons
    }

    // MARK: - Reconciliation

    /// Apply a single server result to local state.
    func reconcile(localId: UUID, serverResult: ScanBatchItemResult) {
        guard let pending = fetchPendingScan(localId: localId) else { return }

        switch serverResult.code {
        case "OK":
            pending.status = .synced
            pending.serverBoxItemId = serverResult.boxItemId
            pending.lastAttemptAt = .now
            // Mirror is already correct — nothing to do.

        case "ALREADY_PACKED" where serverResult.alreadyPackedInBoxId == pending.boxId:
            // Packed in THIS box: our own earlier write coming back. A batch
            // whose reply was lost is sent again, and the server, rightly,
            // finds the panel already there. That is the scan succeeding, not
            // a conflict; treating it as one sent good scans to "needs
            // checking" and took them off the job's count.
            pending.status = .synced
            pending.lastAttemptAt = .now

        case "ALREADY_PACKED":
            // Server says this panel is in another box. Convert to conflict
            // and remove our optimistic mirror entry so dup detection no
            // longer credits the user for it.
            pending.status = .conflict
            pending.errorCode = serverResult.code
            pending.errorMessage = "Already packed in another box"
            pending.alreadyPackedInBoxId = serverResult.alreadyPackedInBoxId
            removeMirror(consignmentId: pending.consignmentId, panelUid: pending.panelUid)

        case "NOT_ON_MANIFEST":
            pending.status = .conflict
            pending.errorCode = serverResult.code
            pending.errorMessage = "Not on manifest"
            removeMirror(consignmentId: pending.consignmentId, panelUid: pending.panelUid)

        case "WRONG_CONSIGNMENT":
            pending.status = .conflict
            pending.errorCode = serverResult.code
            pending.errorMessage = "Wrong consignment"
            removeMirror(consignmentId: pending.consignmentId, panelUid: pending.panelUid)

        default:
            pending.status = .conflict
            pending.errorCode = serverResult.code
            pending.errorMessage = "Unexpected server response"
        }

        // Re-bind the model into a context to save.
        if let modelContext = pending.modelContext {
            do { try modelContext.save() } catch {
                print("[ScanCacheService.reconcile] save error: \(error)")
            }
        } else {
            context.insert(pending)
            try? context.save()
        }
    }

    /// Mark a batch of scans as rejected with the same reason (e.g. box was
    /// closed mid-flush). User must resolve manually.
    func rejectBatch(localIds: [UUID], reason: String) {
        for id in localIds {
            guard let p = fetchPendingScan(localId: id) else { continue }
            p.status = .rejected
            p.errorCode = "BATCH_REJECTED"
            p.errorMessage = reason
            try? p.modelContext?.save()
        }
    }

    /// Repair drift: anything the server says is packed but we don't have
    /// locally, write into our mirror; anything we have locally but the server
    /// doesn't, leave alone (might be in our pending queue).
    func reconcileFromBoxDetail(consignmentId: String, panels: [BoxItem]) {
        for p in panels {
            let panelUid = "\(p.projectName)|\(p.cabinetName)|\(p.partNumber)"
            let key = "\(consignmentId)|\(panelUid)"
            let predicate = #Predicate<PackedPanelMirror> { $0.compoundKey == key }
            let descriptor = FetchDescriptor<PackedPanelMirror>(predicate: predicate)
            if let existing = (try? context.fetch(descriptor))?.first {
                existing.boxId = p.boxId
                existing.syncedAt = .now
            } else {
                context.insert(PackedPanelMirror(
                    consignmentId: consignmentId,
                    panelUid: panelUid,
                    boxId: p.boxId
                ))
            }
            packedByConsignment[consignmentId, default: [:]][panelUid] = p.boxId
        }
        try? context.save()
    }

    // MARK: - Manual entry support
    //
    // When a label barcode is too damaged to scan, the operator falls back
    // to picking the panel from the cached registry. These helpers expose
    // the registry as a (cabinet → parts) tree, annotated with per-panel
    // "is it already packed and where" so the UI can disable already-packed
    // entries.

    struct CabinetSummary: Hashable, Identifiable {
        let cabinetName: String
        let totalPartCount: Int
        let packedPartCount: Int
        var id: String { cabinetName }
        var isComplete: Bool { totalPartCount > 0 && packedPartCount >= totalPartCount }
        var unpackedCount: Int { max(totalPartCount - packedPartCount, 0) }
    }

    struct CabinetPartEntry: Hashable, Identifiable {
        let panelUid: String
        let cabinetName: String
        let partNumber: String
        let lengthMm: Int
        let widthMm: Int
        let thicknessMm: Int
        let material: String
        /// nil = not packed; non-nil = the box id where it's packed.
        let packedInBoxId: String?
        var id: String { panelUid }
        var isPacked: Bool { packedInBoxId != nil }
        var dimensionsLabel: String {
            "\(lengthMm) × \(widthMm) × \(thicknessMm) mm"
        }
    }

    /// Returns one CabinetSummary per cabinet name in the registry for this
    /// (manifest, project), with packed counts sourced from the live mirror.
    /// Empty if the registry hasn't been cached yet.
    func cabinets(manifestId: String, projectName: String, consignmentId: String) -> [CabinetSummary] {
        if registryByManifest[manifestId] == nil {
            warmRegistryFromDisk(manifestId: manifestId, projectName: projectName)
        }
        if packedByConsignment[consignmentId] == nil {
            warmPackedFromDisk(consignmentId: consignmentId)
        }
        let registry = registryByManifest[manifestId] ?? [:]
        let packed = packedByConsignment[consignmentId] ?? [:]
        let prefix = "\(projectName)|"

        // Group by cabinetName, only counting rows that belong to this project.
        var totals: [String: Int] = [:]
        var packs: [String: Int] = [:]
        for (uid, entry) in registry where uid.hasPrefix(prefix) {
            totals[entry.cabinetName, default: 0] += 1
            if packed[uid] != nil {
                packs[entry.cabinetName, default: 0] += 1
            }
        }
        return totals.map { name, total in
            CabinetSummary(
                cabinetName: name,
                totalPartCount: total,
                packedPartCount: packs[name] ?? 0
            )
        }
        .sorted { $0.cabinetName.localizedStandardCompare($1.cabinetName) == .orderedAscending }
    }

    /// Returns every part for the given cabinet, annotated with "already
    /// packed in box X" if applicable.
    func parts(manifestId: String, projectName: String, cabinetName: String, consignmentId: String) -> [CabinetPartEntry] {
        if registryByManifest[manifestId] == nil {
            warmRegistryFromDisk(manifestId: manifestId, projectName: projectName)
        }
        if packedByConsignment[consignmentId] == nil {
            warmPackedFromDisk(consignmentId: consignmentId)
        }
        let registry = registryByManifest[manifestId] ?? [:]
        let packed = packedByConsignment[consignmentId] ?? [:]
        let prefix = "\(projectName)|\(cabinetName)|"

        return registry
            .compactMap { uid, entry -> CabinetPartEntry? in
                guard uid.hasPrefix(prefix) else { return nil }
                return CabinetPartEntry(
                    panelUid: uid,
                    cabinetName: entry.cabinetName,
                    partNumber: entry.partNumber,
                    lengthMm: entry.lengthMm,
                    widthMm: entry.widthMm,
                    thicknessMm: entry.thicknessMm,
                    material: entry.material,
                    packedInBoxId: packed[uid]
                )
            }
            .sorted { lhs, rhs in
                // Numeric-aware sort so "Part 2" comes before "Part 10".
                lhs.partNumber.localizedStandardCompare(rhs.partNumber) == .orderedAscending
            }
    }

    // MARK: - Job-level progress (used for live progress + pre-close warning)

    /// Number of panels expected for the (manifest, project) — read from the
    /// cached registry. Returns 0 if the registry isn't cached yet.
    func expectedCount(manifestId: String, projectName: String) -> Int {
        if registryByManifest[manifestId] == nil {
            warmRegistryFromDisk(manifestId: manifestId, projectName: projectName)
        }
        // The registry map is keyed by panelUid. Filter by project prefix.
        let prefix = "\(projectName)|"
        return (registryByManifest[manifestId] ?? [:]).keys
            .filter { $0.hasPrefix(prefix) }
            .count
    }

    /// Number of panels packed across all boxes of the consignment. Counts
    /// the local mirror (server-truth + optimistic offline scans).
    func packedCount(consignmentId: String) -> Int {
        if packedByConsignment[consignmentId] == nil {
            warmPackedFromDisk(consignmentId: consignmentId)
        }
        return packedByConsignment[consignmentId]?.count ?? 0
    }

    /// Panel UIDs that the manifest expects but which haven't been packed
    /// anywhere on the consignment yet. Used by the pre-close warning sheet.
    func missingPanelUids(manifestId: String, projectName: String, consignmentId: String) -> [String] {
        if registryByManifest[manifestId] == nil {
            warmRegistryFromDisk(manifestId: manifestId, projectName: projectName)
        }
        if packedByConsignment[consignmentId] == nil {
            warmPackedFromDisk(consignmentId: consignmentId)
        }
        let prefix = "\(projectName)|"
        let expected = (registryByManifest[manifestId] ?? [:]).keys.filter { $0.hasPrefix(prefix) }
        let packed = packedByConsignment[consignmentId] ?? [:]
        return expected.filter { packed[$0] == nil }.sorted()
    }

    // MARK: - Pending-scan queries (used by ScanQueueService and views)

    func pendingScans(forBox boxId: String, statuses: [PendingScanStatus]) -> [PendingScan] {
        let raws = Set(statuses.map(\.rawValue))
        let predicate = #Predicate<PendingScan> { p in
            p.boxId == boxId && raws.contains(p.statusRaw)
        }
        let descriptor = FetchDescriptor<PendingScan>(predicate: predicate, sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func allPending(statuses: [PendingScanStatus]) -> [PendingScan] {
        let raws = Set(statuses.map(\.rawValue))
        let predicate = #Predicate<PendingScan> { p in
            raws.contains(p.statusRaw)
        }
        let descriptor = FetchDescriptor<PendingScan>(predicate: predicate, sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func markSyncing(_ scans: [PendingScan]) {
        for s in scans {
            s.status = .syncing
            s.lastAttemptAt = .now
            s.retryCount += 1
        }
        try? scans.first?.modelContext?.save()
    }

    func revertToPending(_ scans: [PendingScan]) {
        for s in scans where s.status == .syncing {
            s.status = .pending
        }
        try? scans.first?.modelContext?.save()
    }

    func deleteSyncedOlderThan(_ cutoff: Date) {
        let raw = PendingScanStatus.synced.rawValue
        let predicate = #Predicate<PendingScan> { p in
            p.statusRaw == raw && p.createdAt < cutoff
        }
        let descriptor = FetchDescriptor<PendingScan>(predicate: predicate)
        if let rows = try? context.fetch(descriptor) {
            for r in rows { context.delete(r) }
            try? context.save()
        }
    }

    func resolveConflict(localId: UUID) {
        guard let p = fetchPendingScan(localId: localId) else { return }
        // User acknowledged — drop the row.
        p.modelContext?.delete(p)
        try? p.modelContext?.save()
    }

    // MARK: - Disk I/O

    private func persistRegistry(
        manifestId: String,
        projectName: String,
        etag: String,
        panels: [PanelRegistryEntry]
    ) async throws {

        // Delete prior rows for this (manifest, project)
        let predicate = #Predicate<CachedPanelRegistry> {
            $0.manifestId == manifestId && $0.projectName == projectName
        }
        let descriptor = FetchDescriptor<CachedPanelRegistry>(predicate: predicate)
        if let existing = try? context.fetch(descriptor) {
            for row in existing { context.delete(row) }
        }

        for p in panels {
            context.insert(CachedPanelRegistry(
                manifestId: manifestId,
                projectName: projectName,
                panelUid: p.panelUid,
                cabinetName: p.cabinetName,
                partNumber: p.partNumber,
                lengthMm: p.lengthMm,
                widthMm: p.widthMm,
                thicknessMm: p.thicknessMm,
                material: p.material
            ))
        }

        // Upsert meta
        let metaKey = "\(manifestId)|\(projectName)"
        let metaPredicate = #Predicate<CachedRegistryMeta> { $0.compoundKey == metaKey }
        let metaDescriptor = FetchDescriptor<CachedRegistryMeta>(predicate: metaPredicate)
        if let meta = (try? context.fetch(metaDescriptor))?.first {
            meta.etag = etag
            meta.fetchedAt = .now
            meta.panelCount = panels.count
        } else {
            context.insert(CachedRegistryMeta(
                manifestId: manifestId,
                projectName: projectName,
                etag: etag,
                panelCount: panels.count
            ))
        }

        try context.save()
    }

    private func persistPackedPanels(consignmentId: String, panels: [PackedPanelEntry]) async throws {

        // Replace mirror rows for this consignment with the server truth.
        let predicate = #Predicate<PackedPanelMirror> { $0.consignmentId == consignmentId }
        let descriptor = FetchDescriptor<PackedPanelMirror>(predicate: predicate)
        if let existing = try? context.fetch(descriptor) {
            for row in existing { context.delete(row) }
        }
        for p in panels {
            context.insert(PackedPanelMirror(
                consignmentId: consignmentId,
                panelUid: p.panelUid,
                boxId: p.boxId
            ))
        }
        try context.save()
    }

    private func warmRegistryFromDisk(manifestId: String, projectName: String) {
        let predicate = #Predicate<CachedPanelRegistry> {
            $0.manifestId == manifestId && $0.projectName == projectName
        }
        let descriptor = FetchDescriptor<CachedPanelRegistry>(predicate: predicate)
        let rows = (try? context.fetch(descriptor)) ?? []
        var map = registryByManifest[manifestId] ?? [:]
        for r in rows {
            map[r.panelUid] = CachedRegistryEntry(
                panelUid: r.panelUid,
                cabinetName: r.cabinetName,
                partNumber: r.partNumber,
                lengthMm: r.lengthMm,
                widthMm: r.widthMm,
                thicknessMm: r.thicknessMm,
                material: r.material
            )
        }
        registryByManifest[manifestId] = map
    }

    private func warmPackedFromDisk(consignmentId: String) {
        let predicate = #Predicate<PackedPanelMirror> { $0.consignmentId == consignmentId }
        let descriptor = FetchDescriptor<PackedPanelMirror>(predicate: predicate)
        let rows = (try? context.fetch(descriptor)) ?? []
        var map: [String: String] = [:]
        for r in rows { map[r.panelUid] = r.boxId }
        packedByConsignment[consignmentId] = map
    }

    private func fetchMeta(manifestId: String, projectName: String) -> CachedRegistryMeta? {
        let key = "\(manifestId)|\(projectName)"
        let predicate = #Predicate<CachedRegistryMeta> { $0.compoundKey == key }
        let descriptor = FetchDescriptor<CachedRegistryMeta>(predicate: predicate)
        return (try? context.fetch(descriptor))?.first
    }

    private func fetchPendingScan(localId: UUID) -> PendingScan? {
        let key = localId.uuidString
        let predicate = #Predicate<PendingScan> { $0.localId == key }
        let descriptor = FetchDescriptor<PendingScan>(predicate: predicate)
        return (try? context.fetch(descriptor))?.first
    }

    private func removeMirror(consignmentId: String, panelUid: String) {
        let key = "\(consignmentId)|\(panelUid)"
        let predicate = #Predicate<PackedPanelMirror> { $0.compoundKey == key }
        let descriptor = FetchDescriptor<PackedPanelMirror>(predicate: predicate)
        if let existing = try? context.fetch(descriptor) {
            for r in existing { context.delete(r) }
            try? context.save()
        }
        packedByConsignment[consignmentId]?.removeValue(forKey: panelUid)
    }
}
