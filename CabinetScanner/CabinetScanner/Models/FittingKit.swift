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
    /// The open "not enough on the shelf" reports. Nil from a server that
    /// predates shortages.
    let shortages: [KitShortage]?
    /// A sentence to show as it is: shortages couldn't be read.
    let shortagesProblem: String?
    /// Whether the job goes out with a kit at all. Nil from an older server.
    let need: KitNeed?

    private enum CodingKeys: String, CodingKey {
        case ok, kit, kitProblem, picking, photos, pickingProblem, shortages, shortagesProblem, need
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decode(Bool.self, forKey: .ok)
        kit = try c.decodeIfPresent(FittingKit.self, forKey: .kit)
        kitProblem = try c.decodeIfPresent(String.self, forKey: .kitProblem)
        picking = try c.decodeIfPresent(KitPicking.self, forKey: .picking)
        photos = try c.decode([KitPhoto].self, forKey: .photos)
        pickingProblem = try c.decodeIfPresent(String.self, forKey: .pickingProblem)
        // Shortages are an extra: anything unexpected in them mustn't stop the
        // kit itself from loading.
        shortages = try? c.decodeIfPresent([KitShortage].self, forKey: .shortages)
        shortagesProblem = try? c.decodeIfPresent(String.self, forKey: .shortagesProblem)
        need = try? c.decodeIfPresent(KitNeed.self, forKey: .need)
    }
}

/// Whether a job goes out with a fitting kit: what despatch decides the kit
/// box label by.
struct KitNeed: Decodable, Hashable {
    /// "needed", "not_needed" or "check" (a person should look).
    let state: String
    /// "No fitting kit"
    let label: String
    /// Why, in a sentence, to show as it is.
    let detail: String

    var isNotNeeded: Bool { state == "not_needed" }
}

/// How far a kit has got, on each job in the kit station's queue.
struct KitProgress: Decodable, Hashable {
    let items: Int
    let done: Int
    let unitsRequired: Int
    let unitsPicked: Int
    let complete: Bool
    let started: Bool
    let shortages: [Short]
    let photos: Int
    let lastChange: KitPicking.LastChange?

    struct Short: Decodable, Hashable {
        let key: String
        let label: String
        let short: Int
    }

    var fraction: Double { items > 0 ? Double(done) / Double(items) : 0 }
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

    struct LastChange: Decodable, Hashable {
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
    /// How many open shortages this batch closed, by ticking those items as
    /// fully picked. Nil from a server that predates shortages.
    let shortagesResolved: Int?
}

// MARK: - Shortages
//
// "There aren't enough of this on the shelf." Reported against one item of the
// picking list, shown on Cabinet Lab so it gets ordered, and shown to the next
// picker on the item. Reporting the same item again updates the open one, and
// it closes itself when the item is ticked as fully picked.

struct KitShortage: Decodable, Identifiable, Hashable {
    let id: String
    /// The picking item's key, exactly as `KitPickItem.key`.
    let key: String
    let label: String?
    /// How many more are needed.
    let short: Int
    let note: String?
    let reportedBy: String
    /// ISO 8601, UTC.
    let reportedAt: String
}

/// The answer to POST …/kit/shortages and DELETE …/kit/shortages/:id,
/// refusals included.
struct KitShortageResponse: Decodable {
    let ok: Bool
    let shortage: KitShortage?
    /// Every open shortage on the kit after the change.
    let shortages: [KitShortage]?
    let error: String?
    let reason: String?
}
