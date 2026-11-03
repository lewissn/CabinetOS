import Foundation

/// The `requestId` for a step tap.
///
/// A new id per deliberate tap; the same id only to retry a tap whose answer
/// never came. A tap that failed with no answer is held against the state the
/// step was in: tap again from that same state and it's a retry, which the
/// server can't apply twice. If the step has since moved it's a new tap. A
/// reused id there would replay the old attempt instead of doing anything.
struct StepTapIds {
    private var held: [String: (id: String, state: String)] = [:]

    mutating func id(forStep stepId: String, action: StepActionKind, state: String) -> String {
        let key = "\(stepId)|\(action.rawValue)"
        if let existing = held[key], existing.state == state { return existing.id }
        let id = UUID().uuidString
        held[key] = (id, state)
        return id
    }

    /// The server answered, so the tap is settled either way, unless the answer
    /// is that it's still being sent. A refusal is settled: the server replays
    /// the outcome of an id it has seen, so tapping again with this one would
    /// only repeat the refusal.
    mutating func answered(_ response: StepActionResponse, step stepId: String, action: StepActionKind) {
        let stillSending = !response.ok && response.duplicate == true && response.reason != "shopvox_refused"
        if !stillSending { held["\(stepId)|\(action.rawValue)"] = nil }
    }
}

// MARK: - Station queue

@MainActor
final class StationQueueViewModel: ObservableObject {
    @Published private(set) var stations: [Station] = []
    @Published private(set) var stationsError: String?
    @Published private(set) var queue: StationQueue?
    @Published private(set) var queueError: String?
    /// The job being moved, so one row shows a spinner and the rest wait.
    @Published private(set) var moving: String?
    @Published var outcome: StepActionOutcome?

    private let service: JobIndexService
    private var tapIds = StepTapIds()
    private var loadingStationId: String?

    init(service: JobIndexService = JobIndexService()) {
        self.service = service
    }

    func loadStations() async {
        do {
            stations = try await service.stations()
            stationsError = nil
        } catch {
            // What's on screen is still right if there's already a list.
            if stations.isEmpty {
                stationsError = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func loadQueue(stationId: String) async {
        loadingStationId = stationId
        // Another department's jobs must not sit under this one's name while
        // it loads: somebody would tap one.
        if queue?.station.id != stationId { queue = nil }
        do {
            let fresh = try await service.stationQueue(id: stationId)
            guard loadingStationId == stationId else { return }
            queue = fresh
            queueError = nil
        } catch {
            guard loadingStationId == stationId, !Task.isCancelled else { return }
            queueError = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Start, pause or finish. As on the job screen, success is only reported
    /// from what the server says ShopVOX ended up with.
    func perform(_ action: StepActionKind, on job: StationJob, stationId: String) async {
        guard let stepId = job.shopvoxStepId, moving == nil else { return }
        moving = job.id
        outcome = nil

        let requestId = tapIds.id(forStep: stepId, action: action, state: job.state)
        do {
            let response = try await service.performStepAction(
                jobId: job.jobId, stepId: stepId, action: action, requestId: requestId
            )
            tapIds.answered(response, step: stepId, action: action)
            if response.ok {
                HapticService.success()
                outcome = StepActionOutcome(
                    isSuccess: true,
                    message: successMessage(action, job: job, response: response),
                    isConfirmed: response.confirmed ?? false
                )
            } else {
                HapticService.error()
                outcome = StepActionOutcome(
                    isSuccess: false,
                    message: response.error ?? "ShopVOX would not accept that change.",
                    isConfirmed: false
                )
            }
        } catch {
            HapticService.error()
            outcome = StepActionOutcome(
                isSuccess: false,
                message: (error as? JobIndexError)?.errorDescription ?? error.localizedDescription,
                isConfirmed: false
            )
        }
        moving = nil
        await loadQueue(stationId: stationId)
    }

    private func successMessage(_ action: StepActionKind, job: StationJob, response: StepActionResponse) -> String {
        if response.duplicate == true { return "That change had already been sent. Nothing was sent twice." }
        if response.confirmed != true {
            return response.message ?? "ShopVOX accepted the change, but the new state could not be read back yet."
        }
        switch action {
        case .start: return "\(job.stepName) started for \(job.displayName)."
        case .stop: return "\(job.stepName) paused for \(job.displayName)."
        case .complete: return "\(job.stepName) finished for \(job.displayName)."
        }
    }
}
