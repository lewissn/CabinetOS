import Foundation

// MARK: - Mock Data
// jobIdentifier mirrors the Ops system's source_name / job_identifier convention.
// source_name is derived from the manifest CSV filename (without extension).
// Example: CSV "Lewis Nichols - 29248.csv" → source_name = "Lewis Nichols - 29248"
// The QR code on every label in that job will contain exactly this string.

enum MockData {
    static let manifests: [Manifest] = [
        Manifest(
            id: "manifest-001",
            name: "Week 8 — Production Run",
            createdAt: ISO8601DateFormatter().date(from: "2026-02-20T09:00:00Z")!,
            consignmentCount: 3,
            status: .active
        ),
        Manifest(
            id: "manifest-002",
            name: "Week 7 — Production Run",
            createdAt: ISO8601DateFormatter().date(from: "2026-02-13T09:00:00Z")!,
            consignmentCount: 2,
            status: .active
        ),
    ]

    static let consignments: [String: [Consignment]] = [
        "manifest-001": [
            Consignment(
                id: "cons-001",
                manifestId: "manifest-001",
                // jobIdentifier = source_name = QR code value = CSV filename without extension
                jobIdentifier: "Lewis Nichols - 29248",
                customerName: "Lewis Nichols",
                expectedItemCount: 24,
                packedItemCount: 0,
                status: .open
            ),
            Consignment(
                id: "cons-002",
                manifestId: "manifest-001",
                jobIdentifier: "Sarah Mitchell - 29249",
                customerName: "Sarah Mitchell",
                expectedItemCount: 16,
                packedItemCount: 0,
                status: .open
            ),
            Consignment(
                id: "cons-003",
                manifestId: "manifest-001",
                jobIdentifier: "James Cooper - 29250",
                customerName: "James Cooper",
                expectedItemCount: 32,
                packedItemCount: 0,
                status: .open
            ),
        ],
        "manifest-002": [
            Consignment(
                id: "cons-004",
                manifestId: "manifest-002",
                jobIdentifier: "Emily Watson - 29240",
                customerName: "Emily Watson",
                expectedItemCount: 20,
                packedItemCount: 20,
                status: .complete
            ),
            Consignment(
                id: "cons-005",
                manifestId: "manifest-002",
                jobIdentifier: "David Brown - 29241",
                customerName: "David Brown",
                expectedItemCount: 12,
                packedItemCount: 8,
                status: .open
            ),
        ],
    ]

    // MARK: - Mock packing_panel_registry equivalent
    // In production, this comes from the Ops packing_panel_registry table.
    // Panel UID format (Ops system): "{source_name}|{cabinet_name}|{part_number}"
    // Part numbers are always 1–2 digit numeric strings.
    // Cabinet names are always alphanumeric (never purely numeric).

    static func registryItems(for consignmentId: String) -> [FinishConsignmentResponse.MissingItem] {
        switch consignmentId {
        case "cons-001":
            // 6 cabinets × 4 parts = 24 items for "Lewis Nichols - 29248"
            var items: [FinishConsignmentResponse.MissingItem] = []
            let cabinets = ["LDC", "UDC", "BC1", "TC1", "WC1", "SC1"]
            for cab in cabinets {
                for part in 1...4 {
                    items.append(FinishConsignmentResponse.MissingItem(
                        id: nil,
                        projectName: "Lewis Nichols - 29248", // = source_name = jobIdentifier
                        cabinetName: cab,
                        partNumber: "\(part)"
                    ))
                }
            }
            return items
        case "cons-002":
            // 4 cabinets × 4 parts = 16 items for "Sarah Mitchell - 29249"
            var items: [FinishConsignmentResponse.MissingItem] = []
            let cabinets = ["LDC", "UDC", "BC1", "TC1"]
            for cab in cabinets {
                for part in 1...4 {
                    items.append(FinishConsignmentResponse.MissingItem(
                        id: nil,
                        projectName: "Sarah Mitchell - 29249",
                        cabinetName: cab,
                        partNumber: "\(part)"
                    ))
                }
            }
            return items
        default:
            return []
        }
    }
}

// MARK: - Mock fitting kit
//
// Used by JobIndexService's kit calls when Configuration.apiMode is .mock. Every
// job gets the same small kit, with drawer runners already reported short, so
// the shortage line and sheet can be seen without a server. Responses are built
// as JSON and decoded with the real models, so the decoding is exercised too.

actor MockKitStore {
    static let shared = MockKitStore()

    private struct Line {
        let key: String
        let label: String
        let category: String
        let mapped: Bool
        let required: Int
    }

    private let lines: [Line] = [
        Line(key: "DRAWER_RUNNER_500", label: "Drawer runner 500 mm (pair)", category: "RUNNERS", mapped: true, required: 6),
        Line(key: "HINGE_110", label: "Soft-close hinge 110°", category: "HINGES", mapped: true, required: 12),
        Line(key: "unmapped:LED STRIP 1M", label: "LED STRIP 1M", category: KitPickItem.unmappedCategory, mapped: false, required: 2),
    ]

    /// Job id → item key → count picked.
    private var picks: [String: [String: Int]] = [:]
    /// Job id → open shortages.
    private var shortages: [String: [KitShortage]] = [:]
    private var nextId = 1

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func prepare(_ jobId: String) {
        guard picks[jobId] == nil else { return }
        picks[jobId] = ["DRAWER_RUNNER_500": 2]
        shortages[jobId] = [KitShortage(id: "mock-shortage-0",
                                        key: "DRAWER_RUNNER_500",
                                        label: "Drawer runner 500 mm (pair)",
                                        short: 4,
                                        note: "Only 2 in the box",
                                        reportedBy: "kit-ipad",
                                        reportedAt: Self.iso(Date().addingTimeInterval(-26 * 3600)))]
    }

    func kit(jobId: String) throws -> FittingKitResponse {
        prepare(jobId)
        let picked = picks[jobId] ?? [:]

        var categories: [String] = []
        for line in lines where line.mapped && !categories.contains(line.category) {
            categories.append(line.category)
        }
        let groups: [[String: Any]] = categories.map { category -> [String: Any] in
            let items: [[String: Any]] = lines.filter { $0.mapped && $0.category == category }.map { line -> [String: Any] in
                ["id": line.key, "label": line.label, "qty": line.required]
            }
            return ["category": category, "items": items]
        }
        let unmapped: [[String: Any]] = lines.filter { !$0.mapped }.map { line -> [String: Any] in
            ["name": line.label, "qty": line.required]
        }
        let result: [String: Any] = ["groups": groups, "unmapped": unmapped]
        let kit: [String: Any] = ["source": "mock", "result": result]

        let items: [[String: Any]] = lines.map { line -> [String: Any] in
            let count = picked[line.key] ?? 0
            return ["key": line.key, "label": line.label, "category": line.category, "mapped": line.mapped,
                    "required": line.required, "picked": count,
                    "done": count >= line.required, "over": count > line.required]
        }
        let done = lines.filter { (picked[$0.key] ?? 0) >= $0.required }.count
        let counts: [String: Int] = [
            "items": lines.count,
            "done": done,
            "unitsRequired": lines.reduce(0) { $0 + $1.required },
            "unitsPicked": lines.reduce(0) { $0 + (picked[$1.key] ?? 0) },
        ]
        let noOrphans: [[String: Any]] = []
        let picking: [String: Any] = [
            "items": items,
            "orphans": noOrphans,
            "counts": counts,
            "complete": done == lines.count,
            "started": true,
        ]
        let noPhotos: [[String: Any]] = []
        let open: [[String: Any]] = (shortages[jobId] ?? []).map { Self.json($0) }
        let body: [String: Any] = [
            "ok": true,
            "kit": kit,
            "picking": picking,
            "photos": noPhotos,
            "shortages": open,
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        return try JSONDecoder().decode(FittingKitResponse.self, from: data)
    }

    func savePicks(jobId: String, picks new: [String: Int]) throws -> KitPicksResponse {
        prepare(jobId)
        let unknown = new.keys.filter { key in !lines.contains { $0.key == key } }
        if !unknown.isEmpty {
            return KitPicksResponse(ok: false, changed: nil, picking: nil,
                                    error: "Some of those items aren't on this kit any more.",
                                    reason: "not_on_kit", unknownKeys: Array(unknown), shortagesResolved: nil)
        }
        for (key, value) in new { picks[jobId, default: [:]][key] = max(0, value) }

        // Ticked as fully picked closes the item's shortage, as on the server.
        let before = shortages[jobId]?.count ?? 0
        let picked = picks[jobId] ?? [:]
        shortages[jobId]?.removeAll { shortage in
            guard let line = lines.first(where: { $0.key == shortage.key }) else { return false }
            return (picked[shortage.key] ?? 0) >= line.required
        }
        let resolved = before - (shortages[jobId]?.count ?? 0)

        let state = try kit(jobId: jobId).picking
        return KitPicksResponse(ok: true, changed: new.count, picking: state,
                                error: nil, reason: nil, unknownKeys: nil, shortagesResolved: resolved)
    }

    func reportShortage(jobId: String, key: String, short: Int, note: String?) -> KitShortageResponse {
        prepare(jobId)
        guard let line = lines.first(where: { $0.key == key }) else {
            return refusal("That item isn't on this kit any more. The kit has been reloaded.", reason: "not_on_kit")
        }
        guard short >= 1, (note?.count ?? 0) <= 500 else {
            return refusal("Say how many more are needed (at least 1), with a note of 500 characters or fewer.", reason: "bad_shortage")
        }
        var open = shortages[jobId] ?? []
        // Reporting the same item again updates its open shortage.
        let existing = open.firstIndex { $0.key == key }
        let id = existing.map { open[$0].id } ?? "mock-shortage-\(nextId)"
        if existing == nil { nextId += 1 }
        let shortage = KitShortage(id: id, key: key, label: line.label, short: short, note: note,
                                   reportedBy: "this iPad (mock)", reportedAt: Self.iso(Date()))
        if let existing { open[existing] = shortage } else { open.append(shortage) }
        shortages[jobId] = open
        return KitShortageResponse(ok: true, shortage: shortage, shortages: open, error: nil, reason: nil)
    }

    func clearShortage(jobId: String, shortageId: String) -> KitShortageResponse {
        prepare(jobId)
        guard shortages[jobId]?.contains(where: { $0.id == shortageId }) == true else {
            return refusal("That shortage had already been cleared.", reason: "not_open")
        }
        shortages[jobId]?.removeAll { $0.id == shortageId }
        return KitShortageResponse(ok: true, shortage: nil, shortages: shortages[jobId] ?? [], error: nil, reason: nil)
    }

    // MARK: Stations

    func stations() throws -> [Station] {
        let body: [String: Any] = ["ok": true, "stations": [
            ["id": "kit", "label": "Fitting kits", "steps": [FittingKitViewModel.stepName],
             "hint": "Kits for jobs going out soon. Tick as you pick; the step starts with the first tick."],
            ["id": "cnc", "label": "CNC", "steps": ["CNC - Manufacture"], "hint": "What's booked to cut."],
        ]]
        return try JSONDecoder().decode(StationsResponse.self, from: JSONSerialization.data(withJSONObject: body)).stations
    }

    /// A morning at the kit station: one being picked, two going out today,
    /// one short, one not at kits yet, one with nothing to pick.
    func stationQueue(id: String) throws -> StationQueue {
        let cal = Calendar.london
        func day(_ offset: Int) -> String {
            let date = cal.date(byAdding: .day, value: offset, to: Date())!
            let f = DateFormatter()
            f.calendar = cal
            f.timeZone = cal.timeZone
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        }
        func allow(_ action: String, _ allowed: Bool, _ reason: String? = nil) -> [String: Any] {
            var out: [String: Any] = ["action": action, "allowed": allowed]
            if let reason { out["reason"] = reason }
            return out
        }
        func progress(_ jobId: String) throws -> [String: Any]? {
            let kit = try kit(jobId: jobId)
            guard let picking = kit.picking else { return nil }
            return [
                "items": picking.counts.items, "done": picking.counts.done,
                "unitsRequired": picking.counts.unitsRequired, "unitsPicked": picking.counts.unitsPicked,
                "complete": picking.complete, "started": picking.started,
                "shortages": (kit.shortages ?? []).map { ["key": $0.key, "label": $0.label ?? $0.key, "short": $0.short] },
                "photos": kit.photos.count,
            ]
        }
        func job(_ jobId: String, _ customer: String, so: String, due: Int, state: String, carrier: String = "APC",
                 startedAt: String? = nil, nowAt: String? = nil, picked: [String: Int]? = nil, noKit: Bool = false) throws -> [String: Any] {
            if let picked, self.picks[jobId] == nil {
                self.picks[jobId] = picked
                self.shortages[jobId] = []
            }
            var out: [String: Any] = [
                "jobId": jobId, "customer": customer, "salesOrderNumber": so, "despatchDate": day(due),
                "carrier": carrier, "stepName": FittingKitViewModel.stepName, "shopvoxStepId": "step-\(jobId)", "state": state,
                "actions": ["start": allow("start", state != "started" && state != "pending", state == "pending" ? "Not at kits yet." : nil),
                            "stop": allow("stop", state == "started"),
                            "complete": allow("complete", state != "pending", state == "pending" ? "Not at kits yet." : nil)],
            ]
            if let startedAt { out["startedAt"] = startedAt; out["startedBy"] = "device:kit-ipad" }
            if let nowAt { out["nowAt"] = nowAt }
            if noKit {
                out["kit"] = ["state": "not_needed", "label": "No fitting kit", "detail": "Hinge holes only: nothing to pack."]
                out["autoComplete"] = ["outcome": "waiting", "reason": "Completes after Pack & Wrap."]
            } else {
                out["kit"] = ["state": "needed", "label": "Fitting kit", "detail": "From the fittings list."]
                out["progress"] = try progress(jobId)
            }
            return out
        }

        let inProgress = [try job("mock-job", "Danielle Tucker", so: "12056", due: 0, state: "started",
                                  startedAt: Self.iso(Date().addingTimeInterval(-40 * 60)))]
        let ready = [
            try job("mock-okafor", "R. Okafor", so: "12071", due: 0, state: "ready", picked: [:]),
            try job("mock-hughes", "Hughes Kitchens", so: "12080", due: 1, state: "paused", carrier: "Own van",
                    picked: ["DRAWER_RUNNER_500": 6, "HINGE_110": 12, "unmapped:LED STRIP 1M": 2]),
            try job("mock-patel", "M. Patel", so: "12077", due: 2, state: "paused"),
            try job("mock-byrne", "J. Byrne", so: "12093", due: 3, state: "pending", nowAt: "Sanding", picked: [:]),
        ]
        let noKit = [try job("mock-shah", "A. Shah", so: "12088", due: 1, state: "ready", noKit: true)]
        let body: [String: Any] = [
            "ok": true,
            "station": ["id": "kit", "label": "Fitting kits", "steps": [FittingKitViewModel.stepName],
                        "hint": "Kits for jobs going out soon. Tick as you pick; the step starts with the first tick."],
            "inProgress": id == "kit" ? inProgress : [],
            "ready": id == "kit" ? ready : [],
            "booked": [] as [[String: Any]],
            "noKit": id == "kit" ? noKit : [],
            "noKitMode": "trial",
            "notes": [] as [String],
        ]
        return try JSONDecoder().decode(StationQueue.self, from: JSONSerialization.data(withJSONObject: body))
    }

    private func refusal(_ error: String, reason: String) -> KitShortageResponse {
        KitShortageResponse(ok: false, shortage: nil, shortages: nil, error: error, reason: reason)
    }

    private static func json(_ shortage: KitShortage) -> [String: Any] {
        var out: [String: Any] = ["id": shortage.id, "key": shortage.key, "short": shortage.short,
                                  "reportedBy": shortage.reportedBy, "reportedAt": shortage.reportedAt]
        if let label = shortage.label { out["label"] = label }
        if let note = shortage.note { out["note"] = note }
        return out
    }
}
