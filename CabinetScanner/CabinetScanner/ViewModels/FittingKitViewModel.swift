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
