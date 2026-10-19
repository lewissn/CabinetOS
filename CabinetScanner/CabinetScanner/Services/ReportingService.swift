import Foundation

// MARK: - Reporting Service
//
// Queries Supabase despatch tables directly to compute packing statistics.
// Tables: despatch_consignments, despatch_boxes, despatch_box_panels.

final class ReportingService {

    func fetchReport(for period: ReportingPeriod, deviceId: String) async throws -> ReportingSummary {
        // All Time is worked out by Ops, beside the database. Anything short
        // of an answer from it (no token on this device, a server from before
        // the route, no signal) falls back to working it out here as before.
        if period == .allTime, Configuration.hasDeviceAPIToken,
           let summary = try? await JobIndexService().reportSummary(period: period, deviceId: deviceId) {
            return summary
        }
        return try await computeReport(for: period, deviceId: deviceId)
    }

    private func computeReport(for period: ReportingPeriod, deviceId: String) async throws -> ReportingSummary {
        let (start, end) = period.dateRange()
        let startISO = Self.isoFormatter.string(from: start)
        let endISO = Self.isoFormatter.string(from: end)

        async let consignmentsTask = fetchConsignments(from: startISO, to: endISO)
        async let boxesTask = fetchBoxes(from: startISO, to: endISO)
        async let panelsTask = fetchPanels(from: startISO, to: endISO)
        async let wrappedBoxesTask = fetchWrappedBoxes(from: startISO, to: endISO)

        let consignments = try await consignmentsTask
        let boxes = try await boxesTask
        let panels = try await panelsTask
        let wrappedBoxes = try await wrappedBoxesTask

        let packingSpeed = computePackingSpeed(
            consignments: consignments,
            panels: panels,
            period: period
        )

        let completionRates = computeCompletionRates(
            consignments: consignments,
            boxes: boxes
        )

        let volume = VolumeStats(
            totalConsignments: consignments.count,
            totalBoxes: boxes.count,
            totalItemsScanned: panels.count
        )

        let wrapLeague = computeWrapLeague(wrappedBoxes: wrappedBoxes, deviceId: deviceId)

        return ReportingSummary(
            period: period,
            packingSpeed: packingSpeed,
            completionRates: completionRates,
            volume: volume,
            wrapLeague: wrapLeague
        )
    }

    // MARK: - Queries

    private func fetchConsignments(from start: String, to end: String) async throws -> [RptConsignmentRow] {
        let urlString = Configuration.supabaseURL + "/rest/v1/despatch_consignments"
            + "?select=id,status,started_at,completed_at,created_at"
            + "&created_at=gte.\(Self.encodeFilterValue(start))"
            + "&created_at=lt.\(Self.encodeFilterValue(end))"
            + "&order=created_at.asc,id.asc"   // id breaks ties, so paging is stable

        return try await supabaseGetAll(urlString)
    }

    private func fetchBoxes(from start: String, to end: String) async throws -> [RptBoxRow] {
        let urlString = Configuration.supabaseURL + "/rest/v1/despatch_boxes"
            + "?select=id,consignment_id,opened_at,closed_at,created_at"
            + "&created_at=gte.\(Self.encodeFilterValue(start))"
            + "&created_at=lt.\(Self.encodeFilterValue(end))"
            + "&order=created_at.asc,id.asc"   // id breaks ties, so paging is stable

        return try await supabaseGetAll(urlString)
    }

    private func fetchPanels(from start: String, to end: String) async throws -> [RptPanelRow] {
        let urlString = Configuration.supabaseURL + "/rest/v1/despatch_box_panels"
            + "?select=id,box_id,scanned_at"
            + "&scanned_at=gte.\(Self.encodeFilterValue(start))"
            + "&scanned_at=lt.\(Self.encodeFilterValue(end))"
            + "&order=scanned_at.asc,id.asc"   // id breaks ties, so paging is stable

        return try await supabaseGetAll(urlString)
    }

    /// Uses the explicit wrap event rather than inferring one from a panel
    /// scan. This keeps the league honest when a partially packed box sits
    /// open for a while before it is actually finished.
    private func fetchWrappedBoxes(from start: String, to end: String) async throws -> [RptWrappedBoxRow] {
        let urlString = Configuration.supabaseURL + "/rest/v1/despatch_boxes"
            + "?select=id,box_type,wrapped_at,wrapped_by,wrapped_by_device,wrap_rework_count"
            + "&wrapped_at=gte.\(Self.encodeFilterValue(start))"
            + "&wrapped_at=lt.\(Self.encodeFilterValue(end))"
            + "&order=wrapped_at.asc,id.asc"   // id breaks ties, so paging is stable

        return try await supabaseGetAll(urlString)
    }

    // MARK: - Computation

    private func computePackingSpeed(
        consignments: [RptConsignmentRow],
        panels: [RptPanelRow],
        period: ReportingPeriod
    ) -> PackingSpeedStats {
        // Average completion time for consignments that have both started_at and completed_at
        let completionTimes: [Double] = consignments.compactMap { row in
            guard let startStr = row.startedAt,
                  let endStr = row.completedAt,
                  let startDate = Self.parseISO(startStr),
                  let endDate = Self.parseISO(endStr)
            else { return nil }
            return endDate.timeIntervalSince(startDate) / 60.0  // minutes
        }

        let avgMinutes: Double
        if completionTimes.isEmpty {
            avgMinutes = 0
        } else {
            avgMinutes = completionTimes.reduce(0, +) / Double(completionTimes.count)
        }

        // All time counts days from the first scan, not from the range's start.
        let days: Int
        if period == .allTime, let first = panels.first.flatMap({ Self.parseISO($0.scannedAt) }) {
            days = ReportingPeriod.workingDays(from: Calendar.london.startOfDay(for: first), to: period.dateRange().end)
        } else {
            days = period.workingDays
        }
        let itemsPerDay = Double(panels.count) / Double(days)

        return PackingSpeedStats(
            averageCompletionMinutes: avgMinutes,
            itemsScannedInPeriod: panels.count,
            averageItemsPerDay: itemsPerDay
        )
    }

    private func computeCompletionRates(
        consignments: [RptConsignmentRow],
        boxes: [RptBoxRow]
    ) -> CompletionRateStats {
        let completed = consignments.filter { $0.status == "completed" }.count
        let open = consignments.filter { $0.status == "scanning" }.count
        let total = consignments.count
        let percentage = total > 0 ? Double(completed) / Double(total) * 100.0 : 0

        let avgBoxes: Double
        if total > 0 {
            avgBoxes = Double(boxes.count) / Double(total)
        } else {
            avgBoxes = 0
        }

        return CompletionRateStats(
            completedConsignments: completed,
            openConsignments: open,
            totalConsignments: total,
            completionPercentage: percentage,
            totalBoxesPacked: boxes.count,
            averageBoxesPerConsignment: avgBoxes
        )
    }

    private func computeWrapLeague(
        wrappedBoxes: [RptWrappedBoxRow],
        deviceId: String
    ) -> WrapLeagueStats {
        let cleanBoxes = wrappedBoxes.filter { $0.wrapReworkCount == 0 }
        let cleanPercentage = wrappedBoxes.isEmpty
            ? 0
            : Double(cleanBoxes.count) / Double(wrappedBoxes.count) * 100

        // Rows arrive oldest-first, so walking backwards counts the current run.
        // Deliberately a quality streak, never a speed streak.
        var teamStreak = 0
        for box in wrappedBoxes.reversed() {
            guard box.wrapReworkCount == 0 else { break }
            teamStreak += 1
        }

        // Grouped by device, because the operator name is free text that a
        // packer can mistype or change at any time.
        var scores: [String: WrapperScore] = [:]
        for box in wrappedBoxes {
            guard let device = trimmedOrNil(box.wrappedByDevice) else { continue }

            var score = scores[device] ?? WrapperScore()
            score.wrappedBoxes += 1
            // Latest non-empty name wins, so renaming in Station Setup takes
            // effect without splitting the row.
            if let name = trimmedOrNil(box.wrappedBy) { score.name = name }
            if box.wrapReworkCount == 0 {
                score.cleanWrappedBoxes += 1
                score.points += WrapScoring.points(forRawType: box.boxType)
            }
            scores[device] = score
        }

        let standings = scores.map { device, score in
            WrapperStanding(
                deviceId: device,
                name: score.name ?? "Unnamed station",
                wrappedBoxes: score.wrappedBoxes,
                cleanWrappedBoxes: score.cleanWrappedBoxes,
                cleanWrapPercentage: score.wrappedBoxes == 0
                    ? 0
                    : Double(score.cleanWrappedBoxes) / Double(score.wrappedBoxes) * 100,
                points: score.points
            )
        }
        .sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            if $0.cleanWrappedBoxes != $1.cleanWrappedBoxes {
                return $0.cleanWrappedBoxes > $1.cleanWrappedBoxes
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return WrapLeagueStats(
            wrappedBoxes: wrappedBoxes.count,
            cleanWrappedBoxes: cleanBoxes.count,
            cleanWrapPercentage: cleanPercentage,
            teamCleanStreak: teamStreak,
            cleanWrapPoints: cleanBoxes.reduce(0) { $0 + WrapScoring.points(forRawType: $1.boxType) },
            standings: standings,
            you: standings.first { $0.deviceId == deviceId }
        )
    }

    private func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - HTTP

    /// Every row, a page at a time.
    ///
    /// Supabase answers at most 1,000 rows per request whatever is asked for,
    /// and says nothing when it stops. A month's panel scans pass that, so
    /// "Panels scanned" read exactly 1,000 and everything worked out from it
    /// was quietly short. Pages are requested until one comes back short.
    private func supabaseGetAll<Row: Decodable>(_ urlString: String) async throws -> [Row] {
        let pageSize = 1000
        // The first page also asks for the total, so the rest (All time is
        // 20,000+ scans) can be fetched at once rather than one after another.
        let (first, total): ([Row], Int?) = try await supabaseGetCounted(urlString + "&limit=\(pageSize)&offset=0")
        guard first.count == pageSize else { return first }
        // A runaway guard: 200,000 rows is far past any period here.
        let pages = min(((total ?? (pageSize * 2)) + pageSize - 1) / pageSize, 200)
        guard pages > 1 else { return first }

        var byOffset: [Int: [Row]] = [0: first]
        try await withThrowingTaskGroup(of: (Int, [Row]).self) { group in
            for page in 1..<pages {
                let offset = page * pageSize
                group.addTask {
                    (offset, try await self.supabaseGet(urlString + "&limit=\(pageSize)&offset=\(offset)"))
                }
            }
            for try await (offset, rows) in group { byOffset[offset] = rows }
        }
        var rows = byOffset.keys.sorted().flatMap { byOffset[$0] ?? [] }
        // Without a total, keep going until a short page.
        if total == nil, (byOffset[(pages - 1) * pageSize]?.count ?? 0) == pageSize {
            var offset = pages * pageSize
            while offset < 200 * pageSize {
                let page: [Row] = try await supabaseGet(urlString + "&limit=\(pageSize)&offset=\(offset)")
                rows.append(contentsOf: page)
                if page.count < pageSize { break }
                offset += pageSize
            }
        }
        return rows
    }

    /// One page, plus the total row count from Content-Range ("0-999/20710").
    private func supabaseGetCounted<Row: Decodable>(_ urlString: String) async throws -> ([Row], Int?) {
        guard let url = URL(string: urlString) else { throw ReportingError.badURL }
        var request = URLRequest(url: url)
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("count=exact", forHTTPHeaderField: "Prefer")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ReportingError.httpError(code, detail: Self.describe(data))
        }
        let total = (http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last).flatMap { Int($0) }
        return (try JSONDecoder().decode([Row].self, from: data), total)
    }

    private func supabaseGet<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw ReportingError.badURL
        }

        var request = URLRequest(url: url)
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ReportingError.httpError(code, detail: Self.describe(data))
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            #if DEBUG
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            print("[ReportingService] Decode failed: \(error)")
            print("[ReportingService] Response preview: \(preview)")
            #endif
            throw error
        }
    }

    // MARK: - Formatters

    /// Timestamps for PostgREST filters, in UTC.
    ///
    /// UTC deliberately, not Europe/London. A London timestamp in summer is
    /// written "2026-09-11T00:00:00+01:00", and a "+" in a URL query string
    /// means a SPACE — so PostgREST received "2026-09-11T00:00:00 01:00" and
    /// answered 400 for the whole of British Summer Time. Reports worked every
    /// winter and broke every March.
    ///
    /// The instant is identical either way; UTC just cannot produce the
    /// character that breaks it. `encodeFilterValue` below is the belt to this
    /// pair of braces, so a future value with a "+" in it is safe regardless.
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Percent-encode a value going into a PostgREST filter.
    ///
    /// `URLComponents` is no help here: "+" is legal in a query string, so it
    /// passes it through unescaped and the server still reads it as a space.
    /// The character set below is `urlQueryAllowed` minus the characters that
    /// carry meaning in a query — which is what makes this correct for any
    /// value, not just the timestamps that exposed it.
    static func encodeFilterValue(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// PostgREST's own words for a failure, when it sent any.
    ///
    /// It answers with `{ message, details, hint, code }`. The message alone
    /// is what a person needs; the rest is noise on a phone screen.
    private static func describe(_ data: Data) -> String? {
        struct Body: Decodable {
            let message: String?
            let hint: String?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            let text = String(data: data.prefix(200), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty ?? true) ? nil : text
        }
        if let hint = body.hint, let message = body.message {
            return "\(message) \(hint)"
        }
        return body.message
    }

    private static func parseISO(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}

// MARK: - Decodable rows

private struct RptConsignmentRow: Decodable {
    let id: String
    let status: String
    let startedAt: String?
    let completedAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, status
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }
}

private struct RptBoxRow: Decodable {
    let id: String
    let consignmentId: String
    let openedAt: String?
    let closedAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case consignmentId = "consignment_id"
        case openedAt = "opened_at"
        case closedAt = "closed_at"
        case createdAt = "created_at"
    }
}

private struct RptPanelRow: Decodable {
    let id: String
    let boxId: String
    let scannedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case boxId = "box_id"
        case scannedAt = "scanned_at"
    }
}

private struct RptWrappedBoxRow: Decodable {
    let id: String
    let boxType: String
    let wrappedAt: String
    let wrappedBy: String?
    let wrappedByDevice: String?
    let wrapReworkCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case boxType = "box_type"
        case wrappedAt = "wrapped_at"
        case wrappedBy = "wrapped_by"
        case wrappedByDevice = "wrapped_by_device"
        case wrapReworkCount = "wrap_rework_count"
    }
}

private struct WrapperScore {
    var name: String?
    var wrappedBoxes = 0
    var cleanWrappedBoxes = 0
    var points = 0
}

// MARK: - Errors

enum ReportingError: LocalizedError {
    case badURL
    /// The status AND what the server said about it.
    ///
    /// The detail is the whole point. This screen reported a bare "HTTP 400"
    /// for months while the server was saying "invalid input syntax for type
    /// timestamp with time zone" every single time — which names the fault
    /// outright. Throwing that away turned a five-minute bug into a standing
    /// one nobody could start on.
    case httpError(Int, detail: String?)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid Supabase URL configuration."
        case .httpError(let code, let detail):
            guard let detail, !detail.isEmpty else {
                return "Reports could not be loaded (HTTP \(code))."
            }
            return "Reports could not be loaded (HTTP \(code)). \(detail)"
        }
    }
}
