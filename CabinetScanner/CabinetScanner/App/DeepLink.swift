import Foundation
import SwiftUI

// MARK: - Deep links
//
// One job, one address, from anywhere.
//
//   cabinetscanner://job/<job_index_id>
//   https://ops.thecabinetshop.co.uk/jobs/<job_index_id>
//
// `job_index_id` is the Ops server's own UUID for the job. It is the right
// identifier for a printed code for three reasons, and the same three the
// server's src/lib/job-index/links.ts gives:
//
//   • Every job in the index has one. The ShopVOX job UUID does not — a row
//     seeded from a sales order has none until a job exists against it.
//   • It never changes. Sales order and JB numbers get re-used and edited.
//   • It discloses nothing. A UUID on a label carries no customer, no value,
//     no address and no credential, which matters because a label on a pallet
//     is readable by everyone who handles it.
//
// Both forms are accepted so the QR code on a label can carry the full https
// URL — scannable by any phone camera, and useful even to someone without
// this app, who lands on the Ops website and signs in there.
//
// Nothing about a link grants access. Opening one with no device token leaves
// the destination pending and sends the person to Settings; the job opens
// once the token is in, which is the app's normal permission check and not a
// special case for links.

enum DeepLink: Equatable {
    case job(id: String)

    /// The custom scheme. Registered in Info.plist.
    static let scheme = "cabinetscanner"

    /// Hosts whose /jobs/<id> links this app will open.
    ///
    /// An allowlist rather than "any https URL": without it, a QR code
    /// pointing at someone else's site would send this app to fetch a job id
    /// from it.
    static let knownHosts: Set<String> = [
        "ops.thecabinetshop.co.uk",
        "localhost",
    ]

    static func parse(_ url: URL) -> DeepLink? {
        // cabinetscanner://job/<id>
        if url.scheme?.lowercased() == scheme {
            guard url.host?.lowercased() == "job" else { return nil }
            let id = url.pathComponents.filter { $0 != "/" }.first
            return id.flatMap(isJobId) .map { DeepLink.job(id: $0) }
        }

        // https://<ops host>/jobs/<id>
        if url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" {
            guard let host = url.host?.lowercased(), knownHosts.contains(host) else { return nil }
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.count == 2, parts[0].lowercased() == "jobs" else { return nil }
            return isJobId(parts[1]).map { DeepLink.job(id: $0) }
        }

        return nil
    }

    /// The index's key is a UUID. Anything else is not one of our links, and
    /// refusing it stops a malformed or probing value reaching the API.
    private static func isJobId(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: trimmed) != nil ? trimmed : nil
    }

    /// The absolute URL for a job — what the Ops website should encode in a
    /// QR code, and what this app would generate if it ever needed to share
    /// one.
    static func webURL(jobId: String, host: String = "ops.thecabinetshop.co.uk") -> URL? {
        URL(string: "https://\(host)/jobs/\(jobId)")
    }
}

// MARK: - Router
//
// Where the app is being asked to go, held outside the view tree so a link
// that arrives before the destination can be shown is not lost.

@MainActor
final class AppRouter: ObservableObject {

    /// The job to open, if any. Cleared once it has been shown.
    @Published var pendingJobId: String?

    /// Which tab to be on. A link that opens a job also moves to the Jobs tab,
    /// because leaving the person on the dashboard with a sheet over it makes
    /// the back gesture do the wrong thing.
    @Published var selectedTab: AppTab = .dashboard

    /// True when a link is waiting on the device being set up. The Settings
    /// screen says so, rather than the link silently doing nothing.
    var isWaitingForAccess: Bool {
        pendingJobId != nil && !Configuration.hasDeviceAPIToken
    }

    func open(_ url: URL) {
        guard let link = DeepLink.parse(url) else { return }
        switch link {
        case .job(let id):
            openJob(id)
        }
    }

    func openJob(_ id: String) {
        // Held whether or not the device can act on it yet. Sending somebody
        // to Settings and then losing where they were going is the failure
        // this avoids.
        pendingJobId = id
        selectedTab = Configuration.hasDeviceAPIToken ? .jobs : .settings
    }

    /// Take the pending job, clearing it.
    ///
    /// Cleared on read so the same job can be scanned again a minute later:
    /// if the value stayed set, a repeat scan would be no change at all and
    /// nothing would happen.
    func consumeJob() -> String? {
        defer { pendingJobId = nil }
        return pendingJobId
    }
}
