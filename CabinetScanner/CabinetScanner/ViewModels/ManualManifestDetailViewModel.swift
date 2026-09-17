import Foundation

@MainActor
final class ManualManifestDetailViewModel: ObservableObject {
    @Published var manifest: ManualManifest
    @Published var boxes: [ManualManifestBox] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var showSummary = false

    private let service = ManualManifestService()

    var openBoxes: [ManualManifestBox] { boxes.filter { $0.isOpen } }
    var closedBoxes: [ManualManifestBox] { boxes.filter { $0.isClosed } }
    var allBoxesClosed: Bool { !boxes.isEmpty && openBoxes.isEmpty }
    var canFinish: Bool { allBoxesClosed && !manifest.isFinished }

    init(manifest: ManualManifest) {
        self.manifest = manifest
    }

    func loadBoxes() async {
        isLoading = true
        errorMessage = nil
        do {
            boxes = try await service.fetchBoxes(manifestId: manifest.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func addBox() async {
        let nextNumber = (boxes.map(\.boxNumber).max() ?? 0) + 1
        do {
            let box = try await service.createBox(manifestId: manifest.id, boxNumber: nextNumber)
            boxes.append(box)
            toastMessage = "Box \(box.boxNumber) created"
            HapticService.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func deleteBox(_ box: ManualManifestBox) async {
        do {
            try await service.deleteBox(id: box.id)
            boxes.removeAll { $0.id == box.id }
            toastMessage = "Box deleted"
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func finishManifest() async {
        do {
            try await service.finishManifest(id: manifest.id)
            manifest = ManualManifest(
                id: manifest.id,
                manifestName: manifest.manifestName,
                courier: manifest.courier,
                status: .finished,
                note: manifest.note,
                createdAt: manifest.createdAt,
                updatedAt: Date()
            )
            toastMessage = "Manifest finished"
            HapticService.success()
            showSummary = true
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }

    func reopenManifest() async {
        do {
            try await service.reopenManifest(id: manifest.id)
            manifest = ManualManifest(
                id: manifest.id,
                manifestName: manifest.manifestName,
                courier: manifest.courier,
                status: .open,
                note: manifest.note,
                createdAt: manifest.createdAt,
                updatedAt: Date()
            )
            toastMessage = "Manifest reopened"
            HapticService.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }
}
