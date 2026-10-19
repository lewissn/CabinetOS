import CabinetDesign
import Foundation
import SwiftUI

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
            let fresh = try await service.fetchBoxes(manifestId: manifest.id)
            // Coming back from a box just closed: it glides from Open to Closed.
            if boxes.isEmpty { boxes = fresh } else { withAnimation(PaperMotion.spring) { boxes = fresh } }
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

    @Published var isDeleting = false

    /// Delete this consignment, its boxes and their items. Returns true once
    /// it's gone, so the screen can close.
    func deleteManifest() async -> Bool {
        guard !isDeleting else { return false }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await service.deleteManifest(id: manifest.id)
            HapticService.success()
            NotificationCenter.default.post(name: .courierConsignmentsChanged, object: manifest.id)
            return true
        } catch {
            errorMessage = "The consignment wasn't deleted: \(error.localizedDescription)"
            HapticService.error()
            return false
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
            // The moment plays its own haptics; the summary follows it.
            let outcome = finishOutcome
            MomentCenter.shared.play(FinishMoment(
                name: manifest.manifestName,
                boxCount: boxes.count,
                movedJobOn: outcome?.stepsCompleted == true && outcome?.alreadyCompleted != true,
                onDone: { [weak self] in self?.showSummary = true }
            ))
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
