import Foundation

// MARK: - Kit pick queue
//
// Ticks reach the picker's screen at once and the server when they can. Counts
// are absolute, so only the latest value per item matters: a dropped connection
// leaves one value per item waiting, kept across launches, and they all go in
// one batch when the connection is back.

@MainActor
final class KitPickQueue: ObservableObject {
    static let shared = KitPickQueue()

    /// Job id → item key → the count waiting to send.
    @Published private(set) var pending: [String: [String: Int]] = [:]
    /// The newest picking state the server has sent for each job.
    @Published private(set) var picking: [String: KitPicking] = [:]
    /// Why a job's ticks are waiting, or what happened to them.
    @Published private(set) var problems: [String: String] = [:]
    /// Bumped when the server says a job's kit has changed, so an open screen
    /// knows to read it again.
    @Published private(set) var kitChanges: [String: Int] = [:]

    private let service = JobIndexService()
    private let defaults = UserDefaults.standard
    private let storageKey = "kitPicks.pending"
    /// How long to gather ticks: a picker working down a list shouldn't send a
    /// request per tick.
    private let gatherDelay: Duration = .milliseconds(500)
    private let retryDelay: Duration = .seconds(30)

    private var sending: Set<String> = []
    private var scheduled: [String: Task<Void, Never>] = [:]
    /// Bumped per job whenever a newer state arrives, so a read that was already
    /// in flight can't put older counts back on screen.
    private var revisions: [String: Int] = [:]

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([String: [String: Int]].self, from: data) {
            pending = saved
        }
    }

    // MARK: - What the screen reads

    func displayed(jobId: String) -> KitPicking? {
        picking[jobId]?.applying(pending[jobId] ?? [:])
    }

    func waitingCount(jobId: String) -> Int {
        pending[jobId]?.count ?? 0
    }

    func revision(jobId: String) -> Int {
        revisions[jobId] ?? 0
    }

    /// Take a state read by GET …/kit, unless something newer arrived while it
    /// was in flight.
    func adopt(_ state: KitPicking?, jobId: String, readAtRevision: Int) {
        guard revision(jobId: jobId) == readAtRevision else { return }
        picking[jobId] = state
    }

    // MARK: - Changing counts

    func set(jobId: String, key: String, picked: Int) {
        pending[jobId, default: [:]][key] = picked
        problems[jobId] = nil
        save()
        scheduled[jobId]?.cancel()
        scheduled[jobId] = Task { [weak self, gatherDelay] in
            try? await Task.sleep(for: gatherDelay)
            guard !Task.isCancelled else { return }
            await self?.flush(jobId: jobId)
        }
    }

    // MARK: - Sending

    func flushAll() async {
        for jobId in pending.keys {
            await flush(jobId: jobId)
        }
    }

    /// Sends what's waiting for a job until nothing is. A tick made while a
    /// batch is in flight is picked up by the next time round the loop.
    func flush(jobId: String) async {
        guard !sending.contains(jobId) else { return }
        sending.insert(jobId)
        defer { sending.remove(jobId) }

        while let batch = pending[jobId], !batch.isEmpty {
            let response: KitPicksResponse
            do {
                response = try await service.savePicks(jobId: jobId, picks: batch)
            } catch {
                // It said nothing about the batch, so hold on to it. The next
                // tick, a reload, the connection coming back or this retry tries
                // again. The retry is for a server that's down on a working
                // network, where the connection never "comes back".
                switch error as? JobIndexError {
                case .offline, .unreachable:
                    problems[jobId] = "It'll go when the connection is back."
                default:
                    problems[jobId] = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
                }
                scheduleRetry(jobId: jobId)
                return
            }

            if response.ok {
                removeSent(batch, jobId: jobId)
                problems[jobId] = nil
                if let state = response.picking {
                    picking[jobId] = state
                    revisions[jobId, default: 0] += 1
                }
                continue
            }

            // A refusal about the batch won't change by sending it again.
            if response.reason == "not_on_kit", let unknown = response.unknownKeys, !unknown.isEmpty {
                removeKeys(unknown, jobId: jobId)
            } else {
                removeSent(batch, jobId: jobId)
            }
            problems[jobId] = response.reason == "not_on_kit"
                ? "The fittings list has changed, so this kit has been reloaded. Check it against the box."
                : response.error ?? "Some of those ticks weren't accepted."
            kitChanges[jobId, default: 0] += 1
            if response.reason != "not_on_kit" { return }
        }
    }

    private func scheduleRetry(jobId: String) {
        scheduled[jobId]?.cancel()
        scheduled[jobId] = Task { [weak self, retryDelay] in
            try? await Task.sleep(for: retryDelay)
            guard !Task.isCancelled else { return }
            await self?.flush(jobId: jobId)
        }
    }

    /// Clear what was sent, keeping any item changed again since.
    private func removeSent(_ batch: [String: Int], jobId: String) {
        for (key, value) in batch where pending[jobId]?[key] == value {
            pending[jobId]?[key] = nil
        }
        tidy(jobId: jobId)
    }

    private func removeKeys(_ keys: [String], jobId: String) {
        for key in keys { pending[jobId]?[key] = nil }
        tidy(jobId: jobId)
    }

    private func tidy(jobId: String) {
        if pending[jobId]?.isEmpty == true { pending[jobId] = nil }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
