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

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            summary = try await service.fetchReport(for: selectedPeriod, deviceId: deviceId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
