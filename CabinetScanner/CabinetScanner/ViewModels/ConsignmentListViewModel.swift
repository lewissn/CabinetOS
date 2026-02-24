import Foundation

@MainActor
final class ConsignmentListViewModel: ObservableObject {
    @Published var consignments: [Consignment] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let manifestId: String
    let manifestName: String
    private let api: APIServiceProtocol

    init(manifestId: String, manifestName: String, api: APIServiceProtocol = ServiceContainer.shared.api) {
        self.manifestId = manifestId
        self.manifestName = manifestName
        self.api = api
    }

    func loadConsignments() async {
        isLoading = true
        errorMessage = nil
        do {
            consignments = try await api.fetchConsignments(manifestId: manifestId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
