import Foundation

@MainActor
final class ManualManifestDetailViewModel: ObservableObject {
    @Published var manifest: ManualManifest
    @Published var boxes: [ManualManifestBox] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var toastMessage: String?
    @Published var showSummary = false
    /// What ShopVOX did when a job-linked consignment was finished, kept on
    /// screen: a completed step can't be undone, so the outcome must be readable.
    @Published var finishOutcome: CourierConsignmentFinished?
    @Published var isFinishing = false

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

    /// Finish the consignment.
    ///
    /// One raised from a job page goes through Ops, which closes it and then
    /// completes Pack & Wrap and Despatch in ShopVOX, so the job moves on
    /// without anyone doing it by hand. One typed at the bench has no job
    /// behind it and is closed in Supabase as before.
    func finishManifest() async {
        guard !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }
        errorMessage = nil
        do {
            if let jobId = manifest.jobIndexId {
                let result = try await JobIndexService().finishConsignment(jobId: jobId, manifestId: manifest.id)
                finishOutcome = result
                guard result.ok, result.finished != false else {
                    errorMessage = result.error ?? result.message ?? "The consignment couldn't be finished."
                    HapticService.error()
                    return
                }
            } else {
                try await service.finishManifest(id: manifest.id)
            }
            manifest = withStatus(.finished)
            toastMessage = "Manifest finished"
            HapticService.success()
            showSummary = true
        } catch {
            errorMessage = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
            HapticService.error()
        }
    }

    /// The same manifest with a new status, keeping its link to the job.
    private func withStatus(_ status: ManualManifest.ManualManifestStatus) -> ManualManifest {
        var copy = ManualManifest(
            id: manifest.id,
            manifestName: manifest.manifestName,
            courier: manifest.courier,
            status: status,
            note: manifest.note,
            createdAt: manifest.createdAt,
            updatedAt: Date()
        )
        copy.jobIndexId = manifest.jobIndexId
        copy.jobReference = manifest.jobReference
        copy.stepsCompletedAt = finishOutcome?.stepsCompleted == true ? Date() : manifest.stepsCompletedAt
        return copy
    }

    func reopenManifest() async {
        do {
            try await service.reopenManifest(id: manifest.id)
            manifest = withStatus(.open)
            toastMessage = "Manifest reopened"
            HapticService.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }
}
