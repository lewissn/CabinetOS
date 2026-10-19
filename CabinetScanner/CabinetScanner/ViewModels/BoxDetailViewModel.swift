import Foundation

@MainActor
final class BoxDetailViewModel: ObservableObject {
    @Published var box: Box
    @Published var items: [BoxItem] = []
    @Published var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var pendingCount: Int = 0
    @Published var conflictCount: Int = 0
    @Published var jobExpectedCount: Int = 0
    @Published var jobPackedCount: Int = 0
    @Published var missingPanelUids: [String] = []

    let manifestId: String
    let consignmentId: String
    let customerName: String
    let manifestName: String
    private let api: APIServiceProtocol
    private let realtime = RealtimeService()
    private let cache: ScanCacheService
    private var queueObserver: NSObjectProtocol?

    /// `customerName` is the consignment's `job_identifier` — same value the
    /// server stores as `source_name` in `packing_panel_registry`. Used as
    /// `projectName` for cache pre-warming.
    var projectName: String { customerName }

    var shippingMethod: String {
        let name = manifestName
        guard let firstDigit = name.firstIndex(where: { $0.isNumber }) else { return name }
        return String(name[name.startIndex..<firstDigit]).trimmingCharacters(in: .whitespaces)
    }

    init(
        box: Box,
        manifestId: String,
        consignmentId: String,
        customerName: String,
        manifestName: String,
        api: APIServiceProtocol = ServiceContainer.shared.api,
        cache: ScanCacheService = ScanCacheService.shared
    ) {
        self.box = box
        self.manifestId = manifestId
        self.consignmentId = consignmentId
        self.customerName = customerName
        self.manifestName = manifestName
        self.api = api
        self.cache = cache

        // Subscribe to queue changes so badge counts refresh as scans drain.
        queueObserver = NotificationCenter.default.addObserver(
            forName: ScanQueueService.queueDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshQueueCounts() }
        }
    }

    deinit {
        if let queueObserver {
            NotificationCenter.default.removeObserver(queueObserver)
        }
    }

    func loadBoxDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            let (updatedBox, boxItems) = try await api.fetchBoxDetail(boxId: box.id)
            self.box = updatedBox
            self.items = boxItems

            // Record this box as the most recently opened so the Packaging
            // home tab can offer a one-tap "Resume packing" link.
            if updatedBox.isOpen {
                RecentActivityService.recordOpened(
                    box: updatedBox,
                    consignmentId: consignmentId,
                    manifestId: manifestId,
                    manifestName: manifestName,
                    customerName: customerName
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        hasLoaded = true

        // Pre-warm the offline cache in parallel; failures fall back silently.
        if Configuration.useOfflineQueue {
            Task.detached { [cache, manifestId, projectName, consignmentId, items] in
                async let r: () = cache.loadRegistry(manifestId: manifestId, projectName: projectName)
                async let p: () = cache.loadPackedPanels(consignmentId: consignmentId)
                _ = await (r, p)
                // Repair any drift between the freshly-loaded box and our local mirror.
                await cache.reconcileFromBoxDetail(consignmentId: consignmentId, panels: items)
            }
            await refreshQueueCounts()
            await refreshJobProgress()
        }
    }

    func refreshQueueCounts() async {
        let pending = await cache.pendingScans(forBox: box.id, statuses: [.pending, .syncing])
        let conflicts = await cache.pendingScans(forBox: box.id, statuses: [.conflict, .rejected])
        self.pendingCount = pending.count
        self.conflictCount = conflicts.count
    }

    /// Refresh the job-level progress counters that drive the live progress
    /// pill and the pre-close warning sheet.
    func refreshJobProgress() async {
        let expected = await cache.expectedCount(manifestId: manifestId, projectName: projectName)
        let packed = await cache.packedCount(consignmentId: consignmentId)
        let missing = await cache.missingPanelUids(
            manifestId: manifestId,
            projectName: projectName,
            consignmentId: consignmentId
        )
        self.jobExpectedCount = expected
        self.jobPackedCount = packed
        self.missingPanelUids = missing
    }

    /// Friendly labels for the missing panel UIDs (cabinet — part). Used by
    /// the pre-close warning sheet.
    var missingPanelLabels: [String] {
        missingPanelUids.map { uid in
            let parts = uid.split(separator: "|", maxSplits: 2).map(String.init)
            if parts.count >= 3 {
                return "\(parts[1]) — Part \(parts[2])"
            }
            return uid
        }
    }

    func startPolling() {
        realtime.startPolling { [weak self] in
            guard let self = self else { return }
            await self.refreshQuietly()
        }
    }

    func stopPolling() {
        realtime.stopPolling()
    }

    func deleteItem(_ item: BoxItem) async {
        do {
            try await api.deleteBoxItem(boxItemId: item.id)
            items.removeAll { $0.id == item.id }
            toastMessage = "Item removed"
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    /// Returns the reward to show for a successful close, or nil if it failed.
    func closeBox(wrappedBy: String?, deviceId: String) async -> WrapReward? {
        do {
            let boxType = box.boxType
            let closed = try await api.closeBox(
                boxId: box.id,
                wrappedBy: wrappedBy,
                wrappedByDevice: deviceId
            )
            self.box = closed
            HapticService.seal()
            SealCenter.shared.mark(closed.id)
            return WrapStatsService.shared.recordWrap(boxType: boxType)
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return nil
        }
    }

    func reopenBox(deviceId: String) async -> Bool {
        do {
            try await api.reopenBox(
                boxId: box.id,
                consignmentId: consignmentId,
                reopenedByDevice: deviceId
            )
            let (updatedBox, _) = try await api.fetchBoxDetail(boxId: box.id)
            self.box = updatedBox
            toastMessage = "Box reopened"
            HapticService.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }

    func deleteBox() async -> Bool {
        do {
            try await api.deleteBox(boxId: box.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }

    private func refreshQuietly() async {
        do {
            let (updatedBox, boxItems) = try await api.fetchBoxDetail(boxId: box.id)
            await MainActor.run {
                self.box = updatedBox
                self.items = boxItems
            }
            if Configuration.useOfflineQueue {
                await cache.reconcileFromBoxDetail(consignmentId: consignmentId, panels: boxItems)
                await refreshQueueCounts()
                await refreshJobProgress()
            }
        } catch {
            // Silently ignore polling errors
        }
    }
}
