import Foundation

@MainActor
final class ReportingViewModel: ObservableObject {

    @Published var selectedPeriod: ReportingPeriod = .today {
        didSet {
            guard oldValue != selectedPeriod else { return }
            Task { await refresh() }
        }
    }

    @Published private(set) var summary: ReportingSummary = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    /// Identifies which standing belongs to this phone. Set once by the view.
    var deviceId: String = ""

    private let service = ReportingService()

    /// When the figures on screen were fetched, and for which period.
    private var loadedAt: Date?
    private var loadedPeriod: ReportingPeriod?

    /// Fetch the selected period. Figures already showing for this period
    /// stay up while they reload, rather than the page dropping to "Loading".
    func refresh() async {
        let period = selectedPeriod
        if loadedPeriod != period { isLoading = true }
        errorMessage = nil
        do {
            let result = try await service.fetchReport(for: period, deviceId: deviceId)
            // Switched period while this was loading: that request owns the page.
            guard period == selectedPeriod else { return }
            summary = result
            loadedAt = .now
            loadedPeriod = period
        } catch {
            guard period == selectedPeriod else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Coming back to the tab: refresh only when the figures are a couple of
    /// minutes old. All time reads every scan, so it isn't fetched on a whim.
    func refreshIfStale() async {
        if let loadedAt, loadedPeriod == selectedPeriod, Date.now.timeIntervalSince(loadedAt) < 120 { return }
        await refresh()
    }
}
