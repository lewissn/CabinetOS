import Foundation
import Combine

/// Drains pending scans to the server in batches via `POST /scan-batch`.
/// Idempotent flush — safe to invoke from network-restore hooks, scenePhase
/// transitions, and a periodic timer simultaneously. The actor coalesces
/// concurrent calls.
actor ScanQueueService {
    static let shared = ScanQueueService()

    private let cache: ScanCacheService
    private let api: APIServiceProtocol
    private weak var monitor: NetworkMonitor?

    private var isFlushing = false
    private var timerTask: Task<Void, Never>?
    private var lastFlushFailure: Date?

    /// Notification posted whenever the queue state changes (counts may have
    /// shifted). Views observe this to refresh their badge counts.
    static let queueDidChange = Notification.Name("ScanQueueService.queueDidChange")

    private static let maxBatchSize = 50
    private static let flushIntervalSeconds: UInt64 = 10
    private static let backoffSeconds: UInt64 = 30

    init(
        cache: ScanCacheService = ScanCacheService.shared,
        api: APIServiceProtocol = ServiceContainer.shared.api
    ) {
        self.cache = cache
        self.api = api
    }

    // MARK: - Lifecycle

    func start(monitor: NetworkMonitor) {
        self.monitor = monitor
        if timerTask == nil {
            timerTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: Self.flushIntervalSeconds * 1_000_000_000)
                    await self?.flush()
                }
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Public API

    /// Persist a new scan. Caller is expected to have already written it via
    /// ScanCacheService.recordLocalScan; this entry point is here so the call
    /// site reads naturally and so flush can be triggered immediately.
    func enqueue(_ scan: PendingScan) {
        Task { await flush() }
    }

    func flush() async {
        guard !isFlushing else { return }

        // Honour exponential backoff after a failure
        if let last = lastFlushFailure, Date().timeIntervalSince(last) < Double(Self.backoffSeconds) {
            return
        }

        isFlushing = true
        defer {
            isFlushing = false
            NotificationCenter.default.post(name: Self.queueDidChange, object: nil)
        }

        // Garbage-collect old synced rows once per flush.
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        await cache.deleteSyncedOlderThan(cutoff)

        let pending = await cache.allPending(statuses: [.pending])
        if pending.isEmpty { return }

        // Group by box — batch endpoint is per-box.
        let groups = Dictionary(grouping: pending, by: { $0.boxId })

        for (_, scansForBox) in groups {
            for chunk in scansForBox.chunked(into: Self.maxBatchSize) {
                let isOnline = await (monitor?.isOnline ?? true)
                if !isOnline { return }
                await flushChunk(chunk)
            }
        }
    }

    private func flushChunk(_ scans: [PendingScan]) async {
        guard let first = scans.first else { return }

        await cache.markSyncing(scans)

        let manifestId = first.manifestId
        let consignmentId = first.consignmentId
        let boxId = first.boxId

        let items: [ScanBatchItem] = scans.map {
            ScanBatchItem(
                localId: $0.localId,
                projectName: $0.projectName,
                cabinetName: $0.cabinetName,
                partNumber: $0.partNumber,
                scannedAt: DateFormatters.iso8601.string(from: $0.scannedAt),
                deviceId: $0.deviceId,
                stationId: $0.stationId,
                operator_: $0.operatorName
            )
        }
        let request = ScanBatchRequest(manifestId: manifestId, consignmentId: consignmentId, scans: items)

        do {
            let response = try await api.submitScanBatch(boxId: boxId, request: request)
            if response.ok, let results = response.results {
                for result in results {
                    if let uuid = UUID(uuidString: result.localId) {
                        await cache.reconcile(localId: uuid, serverResult: result)
                    }
                }
                lastFlushFailure = nil
            } else {
                // Whole batch rejected (e.g. BOX_CLOSED) — surface for user.
                let reason = response.message ?? response.reason ?? "Batch rejected"
                let ids = scans.compactMap { UUID(uuidString: $0.localId) }
                await cache.rejectBatch(localIds: ids, reason: reason)
                lastFlushFailure = nil   // not a transient error
            }
        } catch {
            // Transient error (network, 5xx) — revert syncing → pending and back off.
            await cache.revertToPending(scans)
            lastFlushFailure = .now
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
