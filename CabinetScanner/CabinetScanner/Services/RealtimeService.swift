import Foundation
import Combine

/// Provides live updates for box/item changes.
/// MVP uses polling; swap for Supabase Realtime when ready.
final class RealtimeService: ObservableObject {
    private var pollingTimer: Timer?
    private var pollingAction: (() async -> Void)?
    private let interval: Double

    init(interval: Double = Configuration.pollingIntervalSeconds) {
        self.interval = interval
    }

    /// Start polling with the given async action
    func startPolling(action: @escaping () async -> Void) {
        stopPolling()
        self.pollingAction = action

        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let action = self?.pollingAction else { return }
            Task { await action() }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        pollingAction = nil
    }

    deinit {
        stopPolling()
    }
}
