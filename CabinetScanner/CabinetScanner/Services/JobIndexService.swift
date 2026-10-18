import Foundation

// MARK: - Job Index Service
//
// Talks to the Ops server's job-index endpoints:
//
//   GET /api/search?q=              universal search
//   GET /api/job-index/:id          full detail for one job
//   GET /api/job-index/views?view=  production date views
//
// These routes require authentication, unlike the older /api/despatch/*
// routes. The device token is sent as a bearer token when one has been set at
// station setup; without it the server answers 401 and the UI says so plainly
// rather than showing an empty list.

enum JobIndexError: LocalizedError {
    /// No token has been saved on this device yet, so there is nothing to send.
    case noTokenOnDevice
    /// The URL could not be built — a configuration fault, not a server one.
    case notConfigured
    /// The server refused the credential. It explains why; that explanation is
    /// carried here verbatim rather than replaced with a guess, because the
    /// two causes — a wrong token, and a server that was never given any —
    /// need completely different people to fix them.
    case unauthorised(serverMessage: String?, reason: String?)
    case notFound
    /// The server answered, but has no such route — it is running a build from
    /// before the job index shipped.
    case notDeployed
    case server(Int)
    case decoding(String)
    case offline

    var errorDescription: String? {
        switch self {
        case .noTokenOnDevice:
            return "This device has no access token yet. Add it in Settings, then try again."
        case .notConfigured:
            return "This device has not been set up for job search yet."
        case .unauthorised(let serverMessage, _):
            return serverMessage ?? "This device is not authorised. Check its access token in Settings."
        case .notFound:
            return "That job is no longer in the index."
        case .notDeployed:
            return "The server does not have job search yet. It needs the latest deploy."
        case .server(let code):
            return "The server returned an error (\(code))."
        case .decoding(let detail):
            return "The server sent something unexpected. \(detail)"
        case .offline:
            return "No connection. Job search needs to be online."
        }
    }

    /// Whether Settings is where this gets fixed, so the UI can offer that
    /// route rather than only a "Try Again" that will fail identically.
    var isAuthProblem: Bool {
        switch self {
        case .noTokenOnDevice, .unauthorised:
            return true
        default:
            return false
        }
    }

    /// True when the fix is on the server, not on this iPad — so the message
    /// can stop telling a packer to check a setting they cannot change.
    var isServerConfigurationProblem: Bool {
        if case .unauthorised(_, let reason) = self {
            return reason == "device_tokens_not_configured"
        }
        return false
    }
}

// MARK: - Device check
//
// The answer to "why will this device not load jobs?", from the server that is
// refusing it. Mirrors GET /api/auth/device-check.

struct DeviceCheckResult: Decodable {
    let authenticated: Bool
    let message: String?
    let reason: String?
    let nextStep: String?
    let identity: Identity?
    let server: ServerState?

    struct Identity: Decodable {
        let kind: String
        let name: String
    }

    struct ServerState: Decodable {
        let authEnforced: Bool
        let deviceTokensConfigured: Int
        let environment: String
    }
}

/// The `{ ok: false, error, reason }` body every Ops route returns on refusal.
private struct APIErrorBody: Decodable {
    let error: String?
    let reason: String?
}

private struct StepActionRequest: Encodable {
    let action: String
    let requestId: String
}

private struct EmptyBody: Encodable {}

private struct CreateConsignmentBody: Encodable {
    let name: String
    let courier: String?
    let note: String?
}

private struct MarkReadRequest: Encodable {
    let ids: [String]?
    let all: Bool?
    let read: Bool?
}

final class JobIndexService {

    private let apiRoot: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(apiRoot: String = Configuration.apiRoot) {
        self.apiRoot = apiRoot

        // Search is typed into interactively, so it fails fast rather than
        // queueing: a stale result arriving after three more keystrokes is
        // worse than no result.
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    // MARK: - Search

    func search(query: String) async throws -> JobSearchResponse {
        var components = URLComponents(string: apiRoot + "/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        // A 404 on a search cannot mean "no such job" — it means no such route.
        return try await get(components?.url, missingMeans: .notDeployed)
    }

    // MARK: - Detail

    func jobDetail(id: String) async throws -> JobDetail {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        // Here a 404 genuinely does mean the job is gone.
        return try await get(URL(string: apiRoot + "/job-index/" + encoded), missingMeans: .notFound)
    }

    // MARK: - Production views

    func productionView(_ view: ProductionDateView) async throws -> ProductionViewResponse {
        var components = URLComponents(string: apiRoot + "/job-index/views")
        components?.queryItems = [URLQueryItem(name: "view", value: view.rawValue)]
        // A date view is not a single record, so a 404 is a missing route.
        return try await get(components?.url, missingMeans: .notDeployed)
    }

    // MARK: - Transport

    private func get<T: Decodable>(
        _ url: URL?,
        missingMeans: JobIndexError
    ) async throws -> T {
        guard let url else { throw JobIndexError.notConfigured }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Fail here rather than at the server: an unauthenticated round trip
        // returns the same 401 as a wrong token and tells nobody anything.
        guard let token = Configuration.deviceAPIToken, !token.isEmpty else {
            throw JobIndexError.noTokenOnDevice
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, http) = try await send(request)

        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            throw JobIndexError.unauthorised(serverMessage: body?.error, reason: body?.reason)
        case 404:
            throw missingMeans
        default:
            throw JobIndexError.server(http.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? "<binary>"
            print("[JobIndexService] Decode failed for \(url.path): \(error)")
            print("[JobIndexService] Body: \(preview)")
            #endif
            throw JobIndexError.decoding(error.localizedDescription)
        }
    }

    /// One place that turns URLSession's error vocabulary into ours.
    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JobIndexError.server(-1)
            }
            return (data, http)
        } catch let error as URLError
            where error.code == .notConnectedToInternet
                || error.code == .networkConnectionLost
                || error.code == .timedOut
                || error.code == .cannotConnectToHost {
            throw JobIndexError.offline
        }
    }

    // MARK: - Workflow actions

    /// Start, pause or complete a step, and report what ShopVOX ended up with.
    ///
    /// `requestId` is generated once per tap by the caller and resent on a
    /// retry. It is what stops a double-tap, or a retry after a timeout, from
    /// moving the step twice: the server treats a repeat of the same id as the
    /// same attempt and answers with the original outcome.
    func performStepAction(
        jobId: String,
        stepId: String,
        action: StepActionKind,
        requestId: String
    ) async throws -> StepActionResponse {
        let job = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        let step = stepId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stepId

        guard let url = URL(string: apiRoot + "/job-index/\(job)/steps/\(step)") else {
            throw JobIndexError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // A workflow write is worth waiting longer for than a search: the
        // server calls ShopVOX and then re-reads the job to confirm.
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode(
            StepActionRequest(action: action.rawValue, requestId: requestId)
        )

        guard let token = Configuration.deviceAPIToken, !token.isEmpty else {
            throw JobIndexError.noTokenOnDevice
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, http) = try await send(request)

        if http.statusCode == 401 || http.statusCode == 403 {
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            throw JobIndexError.unauthorised(serverMessage: body?.error, reason: body?.reason)
        }

        // Every other status still carries a structured body, and its `error`
        // is the whole point — a refusal from ShopVOX must reach the person in
        // ShopVOX's own words rather than as "something went wrong".
        do {
            return try decoder.decode(StepActionResponse.self, from: data)
        } catch {
            throw JobIndexError.server(http.statusCode)
        }
    }

    // MARK: - Proofs

    /// An authenticated request for a job's proof, streamed through Ops.
    ///
    /// Not the ShopVOX URL. Those are public and unsigned, so going through
    /// the Ops server is what keeps customer artwork behind the same sign-in
    /// as the job it belongs to.
    func proofRequest(jobId: String, thumbnail: Bool = false) throws -> URLRequest {
        let job = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        var components = URLComponents(string: apiRoot + "/job-index/\(job)/proof")
        if thumbnail { components?.queryItems = [URLQueryItem(name: "thumbnail", value: "1")] }

        guard let url = components?.url else { throw JobIndexError.notConfigured }
        guard let token = Configuration.deviceAPIToken, !token.isEmpty else {
            throw JobIndexError.noTokenOnDevice
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45
        return request
    }

    // MARK: - Courier consignments

    /// What a consignment for this job would be called, and whether one is
    /// already open. Read before showing the form, so the name is filled in
    /// and an existing consignment can be pointed at rather than duplicated.
    func consignmentInfo(jobId: String) async throws -> CourierConsignmentInfo {
        let job = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        return try await get(
            URL(string: apiRoot + "/job-index/\(job)/consignment"),
            missingMeans: .notFound
        )
    }

    func createConsignment(
        jobId: String,
        name: String,
        courier: String?,
        note: String?
    ) async throws -> CourierConsignmentCreated {
        let job = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        guard let url = URL(string: apiRoot + "/job-index/\(job)/consignment") else {
            throw JobIndexError.notConfigured
        }
        return try await post(url, body: CreateConsignmentBody(name: name, courier: courier, note: note))
    }

    /// Finish a consignment, completing the job's packing steps in ShopVOX.
    ///
    /// Goes through Ops rather than writing to Supabase directly, because the
    /// ShopVOX credentials live on the server and the two completions have to
    /// be recorded and de-duplicated somewhere a second tap cannot reach.
    func finishConsignment(jobId: String, manifestId: String) async throws -> CourierConsignmentFinished {
        let job = jobId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? jobId
        let manifest = manifestId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? manifestId
        guard let url = URL(string: apiRoot + "/job-index/\(job)/consignment/\(manifest)/finish") else {
            throw JobIndexError.notConfigured
        }
        // Two ShopVOX writes, each followed by a re-read.
        return try await post(url, body: EmptyBody(), timeout: 90)
    }

    // MARK: - Notifications

    func notifications(since: String? = nil, limit: Int = 50) async throws -> NotificationFeed {
        var components = URLComponents(string: apiRoot + "/notifications")
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let since { items.append(URLQueryItem(name: "since", value: since)) }
        components?.queryItems = items
        return try await get(components?.url, missingMeans: .notDeployed)
    }

    /// Mark specific notifications read, or everything this device can see.
    @discardableResult
    func markNotifications(ids: [String] = [], all: Bool = false, read: Bool = true) async throws -> Bool {
        guard let url = URL(string: apiRoot + "/notifications/read") else {
            throw JobIndexError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            MarkReadRequest(ids: ids.isEmpty ? nil : ids, all: all ? true : nil, read: read ? nil : false)
        )

        guard let token = Configuration.deviceAPIToken, !token.isEmpty else {
            throw JobIndexError.noTokenOnDevice
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, http) = try await send(request)
        return (200...299).contains(http.statusCode)
    }

    // MARK: - POST transport

    private func post<Body: Encodable, T: Decodable>(
        _ url: URL,
        body: Body,
        timeout: TimeInterval = 45
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(body)

        guard let token = Configuration.deviceAPIToken, !token.isEmpty else {
            throw JobIndexError.noTokenOnDevice
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, http) = try await send(request)

        if http.statusCode == 401 || http.statusCode == 403 {
            let error = try? decoder.decode(APIErrorBody.self, from: data)
            throw JobIndexError.unauthorised(serverMessage: error?.error, reason: error?.reason)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // A structured refusal is still worth surfacing in the server's
            // own words rather than as a decode failure.
            if let error = try? decoder.decode(APIErrorBody.self, from: data), let message = error.error {
                throw JobIndexError.decoding(message)
            }
            throw JobIndexError.server(http.statusCode)
        }
    }

    // MARK: - Device check
    //
    // Deliberately sends whatever token is saved — including none — and reads
    // the diagnosis out of a 200. The endpoint never refuses, because a 401
    // here would be the same dead end it exists to explain.

    func deviceCheck() async throws -> DeviceCheckResult {
        guard let url = URL(string: apiRoot + "/auth/device-check") else {
            throw JobIndexError.notConfigured
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = Configuration.deviceAPIToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, http) = try await send(request)

        // An older deploy has no such route. Say that, rather than reporting a
        // decode failure for a 404 page.
        guard http.statusCode != 404 else { throw JobIndexError.notDeployed }
        guard (200...299).contains(http.statusCode) else {
            throw JobIndexError.server(http.statusCode)
        }

        do {
            return try decoder.decode(DeviceCheckResult.self, from: data)
        } catch {
            throw JobIndexError.decoding(error.localizedDescription)
        }
    }
}

// MARK: - Date views

/// Ordered the way the workshop uses them: what is late, what is imminent,
/// then the wider picture.
///
/// Week views lead because due dates here land almost entirely on Tuesdays and
/// Fridays — a single-day view shows nothing on a Thursday however complete
/// the index is, so it is a poor thing to open on.
enum ProductionDateView: String, CaseIterable, Identifiable {
    case overdue
    case thisWeek = "this-week"
    case today
    case tomorrow
    case nextWeek = "next-week"
    case upcoming
    case yesterday
    case recentlyCompleted = "recently-completed"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue:           return "Overdue"
        case .thisWeek:          return "This Week"
        case .today:             return "Today"
        case .tomorrow:          return "Tomorrow"
        case .nextWeek:          return "Next Week"
        case .upcoming:          return "Upcoming"
        case .yesterday:         return "Yesterday"
        case .recentlyCompleted: return "Recent"
        }
    }

    var systemImage: String {
        switch self {
        case .overdue:           return "exclamationmark.triangle"
        case .thisWeek:          return "calendar"
        case .today:             return "sun.max"
        case .tomorrow:          return "arrow.uturn.forward"
        case .nextWeek:          return "calendar.badge.plus"
        case .upcoming:          return "calendar.badge.clock"
        case .yesterday:         return "arrow.uturn.backward"
        case .recentlyCompleted: return "checkmark.circle"
        }
    }
}
