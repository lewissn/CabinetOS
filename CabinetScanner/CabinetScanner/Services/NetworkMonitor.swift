import Foundation
import Network
import Combine

/// Lightweight wrapper around NWPathMonitor. Publishes online/offline state
/// and notifies registered handlers when connectivity is restored after an
/// outage — the trigger used by ScanQueueService to flush pending scans.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.cabinetscanner.network-monitor")
    private var restoreHandlers: [() -> Void] = []
    private var hasStarted = false

    private init() {}

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self = self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = online
                if online && wasOffline {
                    let handlers = self.restoreHandlers
                    for h in handlers { h() }
                }
            }
        }
        monitor.start(queue: queue)
    }

    /// Register a closure to run whenever the network transitions from offline
    /// → online. Multiple handlers can coexist.
    func onRestore(_ handler: @escaping () -> Void) {
        restoreHandlers.append(handler)
    }
}
