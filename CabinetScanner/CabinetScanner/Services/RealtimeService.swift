import Foundation
import Combine
import UIKit

/// Provides live updates for box/item changes.
/// MVP uses polling; swap for Supabase Realtime when ready.
///
/// Polling automatically pauses when the app is backgrounded and resumes
/// when foregrounded — saves cellular data and battery, avoids the OS
/// killing timers we don't actually need running. A "catch-up" run fires
/// immediately on resume so the UI is fresh by the time the user looks at it.
final class RealtimeService: ObservableObject {
    private var pollingTimer: Timer?
    private var pollingAction: (() async -> Void)?
    private let interval: Double
    private var didEnterBackgroundObserver: NSObjectProtocol?
    private var willEnterForegroundObserver: NSObjectProtocol?

    init(interval: Double = Configuration.pollingIntervalSeconds) {
        self.interval = interval
    }

    /// Start polling with the given async action.
    func startPolling(action: @escaping () async -> Void) {
        stopPolling()
        self.pollingAction = action

        scheduleTimer()
        installLifecycleObservers()
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        pollingAction = nil
        removeLifecycleObservers()
    }

    deinit {
        stopPolling()
    }

    // MARK: - Private

    private func scheduleTimer() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let action = self?.pollingAction else { return }
            Task { await action() }
        }
    }

    private func installLifecycleObservers() {
        let center = NotificationCenter.default
        didEnterBackgroundObserver = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.pollingTimer?.invalidate()
            self?.pollingTimer = nil
        }
        willEnterForegroundObserver = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.pollingAction != nil else { return }
            // Catch-up run + resume schedule
            if let action = self.pollingAction {
                Task { await action() }
            }
            self.scheduleTimer()
        }
    }

    private func removeLifecycleObservers() {
        if let didEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(didEnterBackgroundObserver)
        }
        if let willEnterForegroundObserver {
            NotificationCenter.default.removeObserver(willEnterForegroundObserver)
        }
        didEnterBackgroundObserver = nil
        willEnterForegroundObserver = nil
    }
}
