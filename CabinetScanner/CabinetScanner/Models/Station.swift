import Foundation

// MARK: - Department stations
//
// GET /api/stations and /api/stations/:id. A tap moves the job's ShopVOX step
// through the same route the job screen uses (performStepAction).

struct StationsResponse: Decodable {
    let ok: Bool
    let stations: [Station]
}

struct Station: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let steps: [String]
    let hint: String

    /// The fitting kit station's rows open the picking list, not the job.
    var isKit: Bool { id == "kit" }
}

struct StationQueue: Decodable {
    let ok: Bool
    let station: Station
    let inProgress: [StationJob]
    let ready: [StationJob]
    /// CNC only: booked to cut today or earlier, step not ready in ShopVOX yet.
    let booked: [StationJob]
    /// Fitting kits only: waiting jobs with nothing to pick. Nil from a server
    /// that predates them.
    let noKit: [StationJob]?
    /// "on": those steps complete by themselves after Pack & Wrap. "trial":
    /// nothing is written yet.
    let noKitMode: String?
    let notes: [String]

    var isEmpty: Bool { inProgress.isEmpty && ready.isEmpty && booked.isEmpty && (noKit ?? []).isEmpty }

    var allJobs: [StationJob] { inProgress + ready + booked + (noKit ?? []) }

    func job(salesOrder: String) -> StationJob? {
        allJobs.first { $0.salesOrderNumber == salesOrder }
    }

    func job(jobId: String) -> StationJob? {
        allJobs.first { $0.jobId == jobId }
    }
}

struct StationJob: Decodable, Identifiable, Hashable {
    let jobId: String
    let customer: String?
    let salesOrderNumber: String?
    let shopifyOrderNumber: String?
    let po: String?
    let despatchDate: String?
    let carrier: String?
    let stepName: String
    /// Null when the step isn't linked to ShopVOX yet, so it can't be moved.
    let shopvoxStepId: String?
    let state: String
    let startedAt: String?
    /// "device:cnc-tablet" or "user:lewis"; null if started in ShopVOX itself.
    let startedBy: String?
    let cutDay: String?
    let areaM2: Double?
    let parts: Int?
    /// The step the job has reached, when this station's step hasn't come up
    /// yet (fitting kits due out soon).
    let nowAt: String?
    /// Fitting kits only: whether the job goes out with a kit.
    let kit: KitNeed?
    /// On the no-kit list: what happens to its ShopVOX step.
    let autoComplete: AutoComplete?
    /// Fitting kits only: how far picking has got. Nil with no kit list, or
    /// from a server that predates it.
    let progress: KitProgress?
    let actions: Actions

    struct AutoComplete: Decodable, Hashable {
        /// "complete", "waiting" or "held".
        let outcome: String
        let reason: String
    }

    struct Actions: Decodable, Hashable {
        let start: StepActionAvailability
        let stop: StepActionAvailability
        let complete: StepActionAvailability
    }

    var id: String { "\(jobId)|\(stepName)" }

    var isRunning: Bool { state == "started" }
    var isHalted: Bool { state == "paused" || state == "idling" || state == "stopped" }
    /// Not reached this station yet: listed because it's due out soon.
    var isPending: Bool { state == "pending" }

    var displayName: String { customer ?? salesOrderNumber.map { "SO \($0)" } ?? "This job" }

    func availability(_ action: StepActionKind) -> StepActionAvailability {
        switch action {
        case .start: actions.start
        case .stop: actions.stop
        case .complete: actions.complete
        }
    }

    /// "cnc-tablet", without the kind of credential in front.
    var startedByName: String? {
        startedBy.map { $0.split(separator: ":", maxSplits: 1).last.map(String.init) ?? $0 }
    }
}
