import Foundation

@MainActor
final class APCDeadlineViewModel: ObservableObject {

    @Published private(set) var state: APCDeadlineState = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service = APCDeadlineService()
    private var timer: Timer?

    /// True when the banner should be visible (APC jobs exist for today).
    var shouldShow: Bool { !state.isEmpty }

    // MARK: - Data loading

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let jobs = try await service.fetchAPCJobsDueToday()
            state = APCDeadlineState(
                jobs: jobs,
                cutoffDate: Self.todayCutoff(),
                now: Date()
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Countdown timer

    /// Start a 30-second timer that refreshes the `now` field for the countdown display.
    func startCountdown() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state = APCDeadlineState(
                    jobs: self.state.jobs,
                    cutoffDate: self.state.cutoffDate,
                    now: Date()
                )
            }
        }
    }

    func stopCountdown() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Helpers

    /// Returns today at 2pm London time.
    private static func todayCutoff() -> Date {
        let cal = Calendar.london
        let today = cal.startOfDay(for: Date())
        return cal.date(bySettingHour: 14, minute: 0, second: 0, of: today)!
    }
}
