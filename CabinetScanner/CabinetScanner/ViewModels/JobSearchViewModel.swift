import Foundation

@MainActor
final class JobSearchViewModel: ObservableObject {

    @Published var query: String = "" {
        didSet { scheduleSearch() }
    }

    @Published private(set) var results: [JobSearchResult] = []
    @Published private(set) var customers: [ShopVoxCustomer] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasSearched = false
    /// What the server understood the query to be, used to explain no-results.
    @Published private(set) var interpretation: QueryInterpretation?

    private let service: JobIndexService
    private var searchTask: Task<Void, Never>?

    /// Below this the query matches too much to be useful.
    private let minimumQueryLength = 2
    /// Long enough to stop firing on every keystroke, short enough to feel live.
    private let debounceNanoseconds: UInt64 = 280_000_000

    init(service: JobIndexService = JobIndexService()) {
        self.service = service
    }

    deinit { searchTask?.cancel() }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isQueryTooShort: Bool {
        !trimmedQuery.isEmpty && trimmedQuery.count < minimumQueryLength
    }

    var showsEmptyResult: Bool {
        hasSearched && !isSearching && errorMessage == nil
            && results.isEmpty && customers.isEmpty
    }

    // MARK: - Searching

    private func scheduleSearch() {
        // Cancel in flight: results for an abandoned query must never land
        // after results for the current one.
        searchTask?.cancel()

        let text = trimmedQuery

        guard text.count >= minimumQueryLength else {
            results = []
            customers = []
            errorMessage = nil
            hasSearched = false
            isSearching = false
            return
        }

        searchTask = Task { [weak self] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }

            await self.performSearch(text)
        }
    }

    private func performSearch(_ text: String) async {
        isSearching = true
        errorMessage = nil

        do {
            let response = try await service.search(query: text)
            guard !Task.isCancelled else { return }

            // A late response for a query the user has moved on from is
            // discarded rather than shown.
            guard text == trimmedQuery else { return }

            results = response.results
            customers = response.customers ?? []
            interpretation = response.interpretedAs
            hasSearched = true
        } catch {
            guard !Task.isCancelled, text == trimmedQuery else { return }
            results = []
            customers = []
            errorMessage = (error as? JobIndexError)?.errorDescription
                ?? error.localizedDescription
            hasSearched = true
        }

        isSearching = false
    }

    func retry() {
        let text = trimmedQuery
        guard text.count >= minimumQueryLength else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in await self?.performSearch(text) }
    }

    func clear() {
        searchTask?.cancel()
        query = ""
    }
}

@MainActor
final class JobDetailViewModel: ObservableObject {

    @Published private(set) var detail: JobDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastError: JobIndexError?

    /// The step currently being moved, so exactly one control shows a spinner
    /// and the rest are disabled — a second tap while the first is in flight
    /// is the mistake this prevents on the app side.
    @Published private(set) var stepInFlight: String?

    /// What ShopVOX said about the last action. Shown as a banner rather than
    /// an alert: a refusal is information, and dismissing a modal to read the
    /// step it refers to is the wrong way round.
    @Published var actionResult: StepActionOutcome?

    /// The job currently loaded. Set by `load(jobId:)` rather than at init,
    /// so one view model can follow a screen that is reused for another job —
    /// which is what SwiftUI does when one pushed detail replaces another.
    private(set) var jobId: String
    private let service: JobIndexService

    /// One id per tap, held so a retry of the SAME tap reuses it and the
    /// server recognises the repeat instead of moving the step twice.
    private var requestIds: [String: String] = [:]

    init(jobId: String, service: JobIndexService = JobIndexService()) {
        self.jobId = jobId
        self.service = service
    }

    /// Load a job, switching to it if it is not the one already held.
    ///
    /// Switching clears the previous job's detail first. Showing one job's
    /// steps under another job's title for the length of a network round trip
    /// is worse than showing a spinner — somebody would act on it.
    func load(jobId newJobId: String? = nil) async {
        if let newJobId, newJobId != jobId {
            jobId = newJobId
            detail = nil
            actionResult = nil
            stepInFlight = nil
            requestIds.removeAll()
        }

        isLoading = true
        errorMessage = nil

        do {
            detail = try await service.jobDetail(id: jobId)
            lastError = nil
        } catch {
            let jobError = error as? JobIndexError
            lastError = jobError
            errorMessage = jobError?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Workflow

    func isMoving(_ step: JobStep) -> Bool { stepInFlight == step.id }

    var isAnyStepMoving: Bool { stepInFlight != nil }

    /// Start, pause or complete a step.
    ///
    /// Success is only ever reported from what the server says ShopVOX ended
    /// up with. A `confirmed: false` answer means the change landed but the
    /// new state could not be read back, and that is shown as its own outcome
    /// rather than as a tick.
    func perform(_ action: StepActionKind, on step: JobStep) async {
        guard let stepId = step.shopvoxStepId, stepInFlight == nil else { return }

        stepInFlight = step.id
        actionResult = nil

        // Reuse the id for a retry of this same tap; a genuinely new tap gets
        // a new one so it is not mistaken for a repeat.
        let key = "\(step.id)|\(action.rawValue)"
        let requestId = requestIds[key] ?? UUID().uuidString
        requestIds[key] = requestId

        do {
            let response = try await service.performStepAction(
                jobId: jobId,
                stepId: stepId,
                action: action,
                requestId: requestId
            )

            if response.ok {
                requestIds[key] = nil
                actionResult = StepActionOutcome(
                    isSuccess: true,
                    message: successMessage(for: action, response: response, step: step),
                    isConfirmed: response.confirmed ?? false
                )
                // Re-read, so the list shows what ShopVOX has rather than what
                // was asked for.
                await load()
            } else {
                actionResult = StepActionOutcome(
                    isSuccess: false,
                    message: response.error ?? "ShopVOX would not accept that change.",
                    isConfirmed: false
                )
                // A step that had moved underneath us needs a fresh read
                // before the buttons mean anything.
                if response.reason == "unknown_step" || response.reason == "not_allowed_from_state" {
                    await load()
                }
            }
        } catch {
            let jobError = error as? JobIndexError
            actionResult = StepActionOutcome(
                isSuccess: false,
                message: jobError?.errorDescription ?? error.localizedDescription,
                isConfirmed: false
            )
        }

        stepInFlight = nil
    }

    private func successMessage(
        for action: StepActionKind,
        response: StepActionResponse,
        step: JobStep
    ) -> String {
        if response.duplicate == true {
            return "That change had already been sent — nothing was sent twice."
        }
        if response.confirmed != true {
            return response.message
                ?? "ShopVOX accepted the change, but the new state could not be read back yet."
        }
        switch action {
        case .start:    return "\(step.name) started in ShopVOX."
        case .stop:     return "\(step.name) paused in ShopVOX."
        case .complete: return "\(step.name) completed in ShopVOX."
        }
    }
}

/// The outcome of one workflow action, as the detail screen shows it.
struct StepActionOutcome: Identifiable, Equatable {
    let id = UUID()
    let isSuccess: Bool
    let message: String
    /// True only when ShopVOX's new state was read back. A success that is not
    /// confirmed is shown differently, because it is a different claim.
    let isConfirmed: Bool
}

@MainActor
final class ProductionViewsViewModel: ObservableObject {

    @Published var selectedView: ProductionDateView = .thisWeek {
        didSet {
            guard oldValue != selectedView else { return }
            Task { await load() }
        }
    }

    @Published private(set) var response: ProductionViewResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: JobIndexService

    init(service: JobIndexService = JobIndexService()) {
        self.service = service
    }

    var jobs: [ProductionJob] { response?.jobs ?? [] }

    func load() async {
        isLoading = true
        errorMessage = nil

        do {
            response = try await service.productionView(selectedView)
        } catch {
            response = nil
            errorMessage = (error as? JobIndexError)?.errorDescription
                ?? error.localizedDescription
        }

        isLoading = false
    }
}
