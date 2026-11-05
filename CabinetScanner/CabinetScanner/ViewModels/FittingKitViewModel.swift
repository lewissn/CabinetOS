import UIKit

// MARK: - Fitting kit

@MainActor
final class FittingKitViewModel: ObservableObject {
    /// The ShopVOX step that finishing a kit completes.
    static let stepName = "Fitting Kit Preparation"

    @Published private(set) var response: FittingKitResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var photos: [KitPhoto] = []
    @Published private(set) var isUploading = false
    @Published private(set) var photoProblem: String?
    /// Open "not enough on the shelf" reports, one per item at most.
    @Published private(set) var shortages: [KitShortage] = []
    /// Why clearing a shortage didn't work. Reporting shows its own problems
    /// in its sheet.
    @Published private(set) var shortageProblem: String?
    /// For the job's name and its fitting kit step.
    @Published private(set) var detail: JobDetail?
    @Published private(set) var isMovingStep = false
    @Published var outcome: StepActionOutcome?

    let jobId: String
    private let service: JobIndexService
    private let queue = KitPickQueue.shared
    private var tapIds = StepTapIds()

    init(jobId: String, service: JobIndexService = JobIndexService()) {
        self.jobId = jobId
        self.service = service
    }

    var kitStep: JobStep? { detail?.steps.first { $0.name == Self.stepName } }

    func load() async {
        isLoading = true
        let readAt = queue.revision(jobId: jobId)
        async let kit = service.fittingKit(jobId: jobId)
        async let job = try? service.jobDetail(id: jobId)
        do {
            let fresh = try await kit
            response = fresh
            photos = fresh.photos
            shortages = fresh.shortages ?? []
            queue.adopt(fresh.picking, jobId: jobId, readAtRevision: readAt)
            errorMessage = nil
        } catch {
            errorMessage = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }
        if let job = await job { detail = job }
        isLoading = false
        // Anything still waiting from earlier gets another go.
        await queue.flush(jobId: jobId)
    }

    // MARK: - Picking

    /// A tick is the whole required count and an untick is none, never "+1".
    func toggle(_ item: KitPickItem) {
        HapticService.light()
        queue.set(jobId: jobId, key: item.key, picked: item.done ? 0 : item.required)
    }

    func setCount(_ picked: Int, for item: KitPickItem) {
        HapticService.light()
        queue.set(jobId: jobId, key: item.key, picked: max(0, picked))
    }

    func takenOut(_ orphan: KitOrphan) {
        HapticService.light()
        queue.set(jobId: jobId, key: orphan.key, picked: 0)
    }

    // MARK: - Shortages

    func shortage(for item: KitPickItem) -> KitShortage? {
        shortages.first { $0.key == item.key }
    }

    /// Nil once the server has it; otherwise the sentence to show.
    func reportShortage(_ item: KitPickItem, short: Int, note: String?) async -> String? {
        do {
            let response = try await service.reportShortage(jobId: jobId, key: item.key, short: short, note: note)
            if response.ok {
                HapticService.success()
                if let open = response.shortages {
                    shortages = open
                } else if let reported = response.shortage {
                    shortages.removeAll { $0.key == reported.key }
                    shortages.append(reported)
                }
                shortageProblem = nil
                return nil
            }
            HapticService.error()
            // The fittings list changed under the picker: show them the new one.
            if response.reason == "not_on_kit" || response.reason == "no_kit" { await load() }
            return response.error ?? "The shortage wasn't recorded. Try again."
        } catch {
            HapticService.error()
            return (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clearShortage(_ shortage: KitShortage) async {
        do {
            let response = try await service.clearShortage(jobId: jobId, shortageId: shortage.id)
            if response.ok {
                HapticService.light()
                if let open = response.shortages {
                    shortages = open
                } else {
                    shortages.removeAll { $0.id == shortage.id }
                }
                shortageProblem = nil
            } else if response.reason == "not_open" {
                // Already closed, which is what was asked for.
                shortageProblem = nil
                await load()
            } else {
                HapticService.error()
                shortageProblem = response.error ?? "The shortage wasn't cleared. Try again."
            }
        } catch {
            HapticService.error()
            shortageProblem = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Photos

    func upload(_ image: UIImage) async {
        isUploading = true
        photoProblem = nil
        defer { isUploading = false }

        guard let jpeg = await Task.detached(priority: .userInitiated, operation: {
            KitPhotoEncoder.jpeg(from: image)
        }).value else {
            photoProblem = "That photo couldn't be prepared. Take it again."
            return
        }
        do {
            photos.append(try await service.uploadKitPhoto(jobId: jobId, jpeg: jpeg))
            HapticService.success()
        } catch {
            HapticService.error()
            photoProblem = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }
    }

    func delete(_ photo: KitPhoto) async {
        do {
            try await service.deleteKitPhoto(jobId: jobId, photoId: photo.id)
            photos.removeAll { $0.id == photo.id }
            photoProblem = nil
        } catch {
            photoProblem = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - The kit's step

    func perform(_ action: StepActionKind) async {
        guard let step = kitStep, let stepId = step.shopvoxStepId, !isMovingStep else { return }
        isMovingStep = true
        outcome = nil
        let requestId = tapIds.id(forStep: stepId, action: action, state: step.state)
        do {
            let response = try await service.performStepAction(jobId: jobId, stepId: stepId, action: action, requestId: requestId)
            tapIds.answered(response, step: stepId, action: action)
            if response.ok {
                HapticService.success()
                outcome = StepActionOutcome(isSuccess: true, message: successMessage(action, response), isConfirmed: response.confirmed ?? false)
            } else {
                HapticService.error()
                outcome = StepActionOutcome(isSuccess: false, message: response.error ?? "ShopVOX would not accept that change.", isConfirmed: false)
            }
        } catch {
            HapticService.error()
            outcome = StepActionOutcome(isSuccess: false, message: (error as? JobIndexError)?.errorDescription ?? error.localizedDescription, isConfirmed: false)
        }
        isMovingStep = false
        if let job = try? await service.jobDetail(id: jobId) { detail = job }
    }

    private func successMessage(_ action: StepActionKind, _ response: StepActionResponse) -> String {
        if response.duplicate == true { return "That change had already been sent. Nothing was sent twice." }
        if response.confirmed != true {
            return response.message ?? "ShopVOX accepted the change, but the new state could not be read back yet."
        }
        switch action {
        case .start: return "Fitting kit started in ShopVOX."
        case .stop: return "Fitting kit paused in ShopVOX."
        case .complete: return "Fitting kit finished in ShopVOX."
        }
    }
}

// MARK: - Photo encoding

/// The server refuses anything of 4 MB or more, so photos are scaled and
/// compressed here. A kit photo only has to show the parts clearly.
enum KitPhotoEncoder {
    private static let limit = 3_800_000

    nonisolated static func jpeg(from image: UIImage) -> Data? {
        for (longestSide, quality) in [(2400.0, 0.75), (2000.0, 0.6), (1600.0, 0.5), (1200.0, 0.45)] {
            if let data = resized(image, longestSide: longestSide).jpegData(compressionQuality: quality), data.count < limit {
                return data
            }
        }
        return nil
    }

    /// Drawing it also bakes in the camera's orientation.
    private nonisolated static func resized(_ image: UIImage, longestSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > longestSide ? longestSide / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
