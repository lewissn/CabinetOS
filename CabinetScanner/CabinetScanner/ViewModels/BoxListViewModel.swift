import CabinetDesign
import Foundation
import SwiftUI

@MainActor
final class BoxListViewModel: ObservableObject {
    @Published var boxes: [Box] = []
    @Published var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?
    @Published var toastMessage: String?

    @Published var showFinishSheet = false
    @Published var missingItems: [FinishConsignmentResponse.MissingItem] = []
    @Published var isFinishing = false
    @Published var isComplete = false

    let consignment: Consignment
    let manifestId: String
    let manifestName: String
    private let api: APIServiceProtocol

    var openBoxes: [Box] { boxes.filter { $0.isOpen } }
    var closedBoxes: [Box] { boxes.filter { $0.isClosed } }

    init(consignment: Consignment, manifestId: String, manifestName: String, api: APIServiceProtocol = ServiceContainer.shared.api) {
        self.consignment = consignment
        self.manifestId = manifestId
        self.manifestName = manifestName
        self.api = api
    }

    func loadBoxes() async {
        isLoading = true
        errorMessage = nil
        do {
            let fresh = try await api.fetchBoxes(consignmentId: consignment.id)
            // Coming back from a box just closed: it glides from Open to Closed.
            if hasLoaded { withAnimation(PaperMotion.spring) { boxes = fresh } } else { boxes = fresh }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        hasLoaded = true
    }

    func createBox(type: Box.BoxType, wrappedBy: String?, deviceId: String) async {
        do {
            var box = try await api.createBox(consignmentId: consignment.id, boxType: type)
            // Non-panel boxes are packed and closed in one action, so they wrap
            // here rather than via the close-box sheet.
            if type.isAutoClose {
                box = try await api.closeBox(
                    boxId: box.id,
                    wrappedBy: wrappedBy,
                    wrappedByDevice: deviceId
                )
                _ = WrapStatsService.shared.recordWrap(boxType: type)
            }
            boxes.append(box)
            toastMessage = type.isAutoClose
                ? "\(type.label) \(box.boxNumber) added and closed"
                : "\(type.label) \(box.boxNumber) added"
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
                toastMessage = "Consignment finished"
                HapticService.success()
                showFinishSheet = false
                isComplete = true
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
