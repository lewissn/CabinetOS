import Foundation

/// Tracks the most recently opened BJS box so the Packaging tab can show a
/// "Resume packing" tile. Persisted in UserDefaults — small JSON payload, no
/// SwiftData dependency.
struct RecentBoxActivity: Codable, Equatable {
    let boxId: String
    let boxNumber: Int
    let boxTypeRaw: String
    let consignmentId: String
    let manifestId: String
    let manifestName: String
    let customerName: String     // = job_identifier / projectName
    let openedAt: Date

    var boxType: Box.BoxType {
        Box.BoxType(rawValue: boxTypeRaw) ?? .panel
    }
}

enum RecentActivityService {
    private static let defaultsKey = "recentBoxActivity.v1"

    /// Record that the user just opened a box. Overwrites any prior entry —
    /// only the most recent matters for the Resume tile.
    static func recordOpened(box: Box, consignmentId: String, manifestId: String, manifestName: String, customerName: String) {
        let activity = RecentBoxActivity(
            boxId: box.id,
            boxNumber: box.boxNumber,
            boxTypeRaw: box.boxType.rawValue,
            consignmentId: consignmentId,
            manifestId: manifestId,
            manifestName: manifestName,
            customerName: customerName,
            openedAt: .now
        )
        if let data = try? JSONEncoder().encode(activity) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Read the most recent activity (or nil if there isn't one).
    static func current() -> RecentBoxActivity? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(RecentBoxActivity.self, from: data)
    }

    /// Clear the recent activity (e.g. after the box is closed and the user
    /// has finished the consignment).
    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}
