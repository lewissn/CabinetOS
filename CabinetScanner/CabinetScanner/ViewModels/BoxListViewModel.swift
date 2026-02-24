import Foundation

@MainActor
final class BoxListViewModel: ObservableObject {
    @Published var boxes: [Box] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var toastMessage: String?

    @Published var showFinishSheet = false
    @Published var missingItems: [FinishConsignmentResponse.MissingItem] = []
    @Published var isFinishing = false

    let consignment: Consignment
    let manifestId: String
    private let api: APIServiceProtocol

    var openBoxes: [Box] { boxes.filter { $0.isOpen } }
    var closedBoxes: [Box] { boxes.filter { $0.isClosed } }

    init(consignment: Consignment, manifestId: String, api: APIServiceProtocol = ServiceContainer.shared.api) {
        self.consignment = consignment
        self.manifestId = manifestId
        self.api = api
    }

    func loadBoxes() async {
        isLoading = true
        errorMessage = nil
        do {
            boxes = try await api.fetchBoxes(consignmentId: consignment.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createBox(type: Box.BoxType) async {
        do {
            var box = try await api.createBox(consignmentId: consignment.id, boxType: type)
            if type.isAutoClose {
                box = try await api.closeBox(boxId: box.id)
            }
            boxes.append(box)
            toastMessage = "\(type.displayName) #\(box.boxNumber) created"
            HapticService.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func deleteBox(_ box: Box) async {
        do {
            try await api.deleteBox(boxId: box.id)
            boxes.removeAll { $0.id == box.id }
            toastMessage = "Box deleted"
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func finishConsignment() async {
        isFinishing = true
        do {
            let response = try await api.finishConsignment(consignmentId: consignment.id)
            if response.ok {
                toastMessage = "Consignment complete!"
                HapticService.success()
                showFinishSheet = false
            } else if let missing = response.missingItems, !missing.isEmpty {
                missingItems = missing
                showFinishSheet = true
            }
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
        isFinishing = false
    }
}
