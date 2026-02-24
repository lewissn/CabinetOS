import Foundation

@MainActor
final class ManifestListViewModel: ObservableObject {
    @Published var manifests: [Manifest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api: APIServiceProtocol

    init(api: APIServiceProtocol = ServiceContainer.shared.api) {
        self.api = api
    }

    func loadManifests() async {
        isLoading = true
        errorMessage = nil
        do {
            manifests = try await api.fetchManifests()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
