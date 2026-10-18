import Foundation

@MainActor
final class ManualBoxDetailViewModel: ObservableObject {
    @Published var box: ManualManifestBox
    @Published var items: [ManualManifestItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var toastMessage: String?

    let manifestName: String
    let courierName: String?
    let isManifestFinished: Bool

    private let service = ManualManifestService()

    init(box: ManualManifestBox, manifestName: String, courierName: String?, isManifestFinished: Bool) {
        self.box = box
        self.manifestName = manifestName
        self.courierName = courierName
        self.isManifestFinished = isManifestFinished
    }

    func loadItems() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await service.fetchItems(boxId: box.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func addScannedItem(triplet: ScanTriplet) async {
        let isDuplicate = items.contains {
            $0.itemType == .label &&
            $0.projectName == triplet.projectName &&
            $0.cabinetName == triplet.cabinetName &&
            $0.partNumber == triplet.partNumber
        }

        if isDuplicate {
            toastMessage = "Duplicate — \(triplet.cabinetName) Part \(triplet.partNumber) already in this box"
            HapticService.error()
            return
        }

        do {
            let item = try await service.upsertLabelItem(
                boxId: box.id,
                projectName: triplet.projectName,
                cabinetName: triplet.cabinetName,
                partNumber: triplet.partNumber
            )
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx] = item
            } else {
                items.append(item)
            }
            HapticService.success()
            HapticService.playTickSound()
            toastMessage = "Added \(triplet.cabinetName) — Part \(triplet.partNumber)"
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func addManualItem(name: String, quantity: Int) async {
        do {
            let item = try await service.upsertManualItem(
                boxId: box.id,
                itemName: name,
                quantity: quantity
            )
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx] = item
            } else {
                items.append(item)
            }
            HapticService.success()
            toastMessage = "Added \(name) (x\(item.qty))"
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func deleteItem(_ item: ManualManifestItem) async {
        do {
            try await service.deleteItem(id: item.id)
            items.removeAll { $0.id == item.id }
            toastMessage = "Item removed"
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func closeBox(lengthMM: Int, widthMM: Int, heightMM: Int, weightKG: Double) async -> Bool {
        do {
            try await service.closeBox(
                id: box.id,
                lengthMM: lengthMM,
                widthMM: widthMM,
                heightMM: heightMM,
                weightKG: weightKG
            )
            box = ManualManifestBox(
                id: box.id,
                manifestId: box.manifestId,
                boxNumber: box.boxNumber,
                status: .closed,
                lengthMM: lengthMM,
                widthMM: widthMM,
                heightMM: heightMM,
                weightKG: weightKG,
                createdAt: box.createdAt
            )
            toastMessage = "Box \(box.boxNumber) closed"
            HapticService.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }

    func closeBoxSimple() async -> Bool {
        do {
            try await service.closeBoxSimple(id: box.id)
            box = ManualManifestBox(
                id: box.id,
                manifestId: box.manifestId,
                boxNumber: box.boxNumber,
                status: .closed,
                lengthMM: box.lengthMM,
                widthMM: box.widthMM,
                heightMM: box.heightMM,
                weightKG: box.weightKG,
                createdAt: box.createdAt
            )
            toastMessage = "Box \(box.boxNumber) closed"
            HapticService.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }

    func updateDimensions(lengthMM: Int, widthMM: Int, heightMM: Int, weightKG: Double) async -> Bool {
        do {
            try await service.updateBoxDimensions(
                id: box.id,
                lengthMM: lengthMM,
                widthMM: widthMM,
                heightMM: heightMM,
                weightKG: weightKG
            )
            box = ManualManifestBox(
                id: box.id,
                manifestId: box.manifestId,
                boxNumber: box.boxNumber,
                status: box.status,
                lengthMM: lengthMM,
                widthMM: widthMM,
                heightMM: heightMM,
                weightKG: weightKG,
                createdAt: box.createdAt
            )
            toastMessage = "Dimensions updated"
            HapticService.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }

    func reopenBox() async -> Bool {
        do {
            try await service.reopenBox(id: box.id)
            box = ManualManifestBox(
                id: box.id,
                manifestId: box.manifestId,
                boxNumber: box.boxNumber,
                status: .open,
                lengthMM: box.lengthMM,
                widthMM: box.widthMM,
                heightMM: box.heightMM,
                weightKG: box.weightKG,
                createdAt: box.createdAt
            )
            toastMessage = "Box reopened"
            HapticService.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
            return false
        }
    }
}
