import Foundation

// MARK: - Notification Service
//
// Keeps this device's copy of the despatch-change feed.
//
// Polling, not push. A push certificate and an APNs key are a separate piece
// of setup that nobody has done, and the device this runs on is a bench iPad
// that is awake and on wifi for the whole shift — so a poll while the app is
// open covers the case that matters, and anything missed while it was shut is
// still there, unread, when it opens again. Nothing is lost by being offline:
// the server holds every notification and read state is per device.
//
// The feed is a shared singleton because three screens show it at once — the
// dashboard notice, the toast, and the notifications tab — and three
// independent pollers would triple the traffic and disagree with each other
// about the unread count.

@MainActor
final class NotificationService: ObservableObject {

    static let shared = NotificationService()

    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefreshed: Date?

    /// The newest notification this device has already shown a toast for.
    /// Nothing that arrived before the app opened is toasted — a bench iPad
    /// picked up after lunch should not fire six banners in a row.
    @Published private(set) var toast: AppNotification?

    private let service: JobIndexService
    private var pollTask: Task<Void, Never>?
    private var seenIds: Set<String> = []
    private var hasCompletedFirstLoad = false

    /// Often enough that a date change reaches the bench while somebody is
    /// still standing at it; rarely enough to be nothing on either server.
    private let pollInterval: Duration = .seconds(60)

    init(service: JobIndexService = JobIndexService()) {
        self.service = service
    }

    deinit { pollTask?.cancel() }

    var unreadNotifications: [AppNotification] {
        notifications.filter { !$0.read }
    }

    /// What the dashboard shows: the unread ones, most pressing first.
    ///
    /// Sorted by severity before recency, so a date brought forward yesterday
    /// outranks a postponement from this morning — the postponement can wait,
    /// the other one is why somebody is about to be late.
    var noticeBoard: [AppNotification] {
        unreadNotifications.sorted { a, b in
            if a.isUrgent != b.isUrgent { return a.isUrgent }
            return a.detectedAt > b.detectedAt
        }
    }

    // MARK: - Loading

    func refresh() async {
        isLoading = true

        do {
            let feed = try await service.notifications()
            apply(feed)
            errorMessage = nil
            lastRefreshed = Date()
        } catch {
            // A failure leaves whatever is already on screen in place. A list
            // that empties itself because wifi dropped is worse than a stale
            // one, and this list is the record of something that has already
            // happened rather than a live reading.
            errorMessage = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }

    private func apply(_ feed: NotificationFeed) {
        let previouslySeen = seenIds
        let arriving = feed.notifications.filter { !previouslySeen.contains($0.id) }

        notifications = feed.notifications
        unreadCount = feed.unreadCount
        seenIds = Set(feed.notifications.map(\.id))

        // Toast only what arrived while this app was open and running, and
        // only the most pressing of a batch — several at once is a banner
        // queue nobody reads.
        if hasCompletedFirstLoad {
            let worthShowing = arriving
                .filter { !$0.read }
                .sorted { a, b in
                    if a.isUrgent != b.isUrgent { return a.isUrgent }
                    return a.detectedAt > b.detectedAt
                }
            if let first = worthShowing.first { toast = first }
        }

        hasCompletedFirstLoad = true
    }

    func dismissToast() { toast = nil }

    // MARK: - Read state

    func markRead(_ notification: AppNotification) async {
        guard !notification.read else { return }
        await setRead([notification.id], read: true)
    }

    func markAllRead() async {
        let ids = unreadNotifications.map(\.id)
        guard !ids.isEmpty else { return }

        // Optimistic, then reconciled by the refresh. Marking read is not a
        // change anyone else can see, so a local echo costs nothing if the
        // request fails and the next poll puts it back.
        applyLocalRead(ids: ids, read: true)

        do {
            _ = try await service.markNotifications(all: true)
        } catch {
            errorMessage = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }
        await refresh()
    }

    func markUnread(_ notification: AppNotification) async {
        await setRead([notification.id], read: false)
    }

    private func setRead(_ ids: [String], read: Bool) async {
        applyLocalRead(ids: ids, read: read)

        do {
            _ = try await service.markNotifications(ids: ids, read: read)
            if read { unreadCount = max(0, unreadCount - ids.count) }
            else { unreadCount += ids.count }
        } catch {
            errorMessage = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
            applyLocalRead(ids: ids, read: !read)
        }
    }

    private func applyLocalRead(ids: [String], read: Bool) {
        let set = Set(ids)
        notifications = notifications.map { n in
            guard set.contains(n.id) else { return n }
            return n.withRead(read)
        }
        unreadCount = notifications.filter { !$0.read }.count
    }

    // MARK: - Polling

    func startPolling() {
        guard pollTask == nil else { return }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.pollInterval else { return }
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return  // cancelled
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}

// MARK: - Local read state

private extension AppNotification {
    /// A copy with `read` flipped.
    ///
    /// Decodable structs have no memberwise initialiser to lean on here, so
    /// this rebuilds the value explicitly. Tedious, but it keeps the model a
    /// plain `let`-only struct rather than making every field mutable for the
    /// sake of one optimistic update.
    func withRead(_ read: Bool) -> AppNotification {
        AppNotification(
            id: id,
            kind: kind,
            title: title,
            body: body,
            severity: severity,
            direction: direction,
            previousDate: previousDate,
            newDate: newDate,
            daysMoved: daysMoved,
            isBroughtForward: isBroughtForward,
            urgencyNote: urgencyNote,
            job: job,
            changedBy: changedBy,
            detectedAt: detectedAt,
            detectionSource: detectionSource,
            linkPath: linkPath,
            read: read,
            readAt: read ? (readAt ?? ISO8601DateFormatter().string(from: Date())) : nil
        )
    }
}
