import Foundation

// MARK: - Fitting kit
//
// GET /api/job-index/:id/kit. The kit is worked out afresh from the job's files
// and the fittings library each time it's read, so nothing here is kept on the
// device except ticks that haven't reached the server yet (see KitPickQueue).

struct FittingKitResponse: Decodable {
    let ok: Bool
    /// Null when the job has no fittings list or ERP fitting rows yet.
    let kit: FittingKit?
    /// A sentence to show as it is: the fittings library couldn't be read.
    let kitProblem: String?
    /// Null when there's no kit, or picking isn't set up on the server.
    let picking: KitPicking?
    let photos: [KitPhoto]
    /// A sentence to show as it is, e.g. the migration hasn't been run.
    let pickingProblem: String?
}

struct FittingKit: Decodable {
    let source: String
    let result: Result

    struct Result: Decodable {
        let groups: [Group]
        let unmapped: [Unmapped]
    }

    struct Group: Decodable {
        let category: String
        let items: [Item]
    }

    struct Item: Decodable {
        let id: String
        let label: String
        let qty: Int
    }

    struct Unmapped: Decodable {
        let name: String
        let qty: Int
    }
}

struct KitPicking: Decodable {
    var items: [KitPickItem]
    var orphans: [KitOrphan]
    var counts: Counts
    var complete: Bool
    let started: Bool
    let lastChange: LastChange?

    struct Counts: Decodable {
        var items: Int
        var done: Int
        let unitsRequired: Int
        let unitsPicked: Int
    }

    struct LastChange: Decodable {
        let by: String
        let at: String
    }

    /// What the picker should see: the server's state with any ticks still
    /// waiting to send laid over it, so a tick holds through a dropped
    /// connection instead of springing back.
    func applying(_ pending: [String: Int]) -> KitPicking {
        guard !pending.isEmpty else { return self }
        var copy = self
        copy.items = items.map { item in
            guard let picked = pending[item.key] else { return item }
            var changed = item
            changed.picked = picked
            changed.done = picked >= item.required
            changed.over = picked > item.required
            return changed
        }
        copy.orphans = orphans.compactMap { orphan in
            guard let picked = pending[orphan.key] else { return orphan }
            if picked == 0 { return nil }
            var changed = orphan
            changed.picked = picked
            return changed
        }
        copy.counts.done = copy.items.filter(\.done).count
        copy.complete = copy.items.allSatisfy(\.done) && copy.orphans.isEmpty
        return copy
    }
}

struct KitPickItem: Decodable, Identifiable {
    /// The library's part id, or "unmapped:<NAME>" for a fitting it doesn't know.
    let key: String
    let label: String
    let category: String
    let mapped: Bool
    let required: Int
    var picked: Int
    var done: Bool
    var over: Bool
    let updatedBy: String?
    let updatedAt: String?

    var id: String { key }
}

/// Picked earlier, but no longer on the kit: it needs taking out of the box.
struct KitOrphan: Decodable, Identifiable {
    let key: String
    var picked: Int
    let updatedBy: String
    let updatedAt: String

    var id: String { key }

    /// Orphans come with a key and no label.
    var displayName: String {
        key.hasPrefix(KitPickItem.unmappedPrefix)
            ? String(key.dropFirst(KitPickItem.unmappedPrefix.count))
            : key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

extension KitPickItem {
    static let unmappedPrefix = "unmapped:"
    static let unmappedCategory = "UNMAPPED"
}

struct KitPhoto: Decodable, Identifiable, Hashable {
    let id: String
    let contentType: String
    let sizeBytes: Int
    let note: String?
    let takenBy: String
    let takenAt: String
}

/// The answer to PUT …/kit/picks, refusals included: a `not_on_kit` carries the
/// keys it wouldn't take.
struct KitPicksResponse: Decodable {
    let ok: Bool
    let changed: Int?
    let picking: KitPicking?
    let error: String?
    let reason: String?
    let unknownKeys: [String]?
}
