import Foundation

// MARK: - Reporting Service
//
// Queries Supabase despatch tables directly to compute packing statistics.
// Tables: despatch_consignments, despatch_boxes, despatch_box_panels.

final class ReportingService {

    func fetchReport(for period: ReportingPeriod, deviceId: String) async throws -> ReportingSummary {
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
            + "&created_at=gte.\(start)"
            + "&created_at=lt.\(end)"
            + "&order=created_at.asc"

        return try await supabaseGet(urlString)
    }

    private func fetchBoxes(from start: String, to end: String) async throws -> [RptBoxRow] {
        let urlString = Configuration.supabaseURL + "/rest/v1/despatch_boxes"
            + "?select=id,consignment_id,opened_at,closed_at,created_at"
            + "&created_at=gte.\(start)"
            + "&created_at=lt.\(end)"
            + "&order=created_at.asc"

        return try await supabaseGet(urlString)
    }

    private func fetchPanels(from start: String, to end: String) async throws -> [RptPanelRow] {
        let urlString = Configuration.supabaseURL + "/rest/v1/despatch_box_panels"
            + "?select=id,box_id,scanned_at"
            + "&scanned_at=gte.\(start)"
            + "&scanned_at=lt.\(end)"
            + "&order=scanned_at.asc"

        return try await supabaseGet(urlString)
    }

    /// Uses the explicit wrap event rather than inferring one from a panel
    /// scan. This keeps the league honest when a partially packed box sits
    /// open for a while before it is actually finished.
    private func fetchWrappedBoxes(from start: String, to end: String) async throws -> [RptWrappedBoxRow] {
        let urlString = Configuration.supabaseURL + "/rest/v1/despatch_boxes"
            + "?select=id,box_type,wrapped_at,wrapped_by,wrapped_by_device,wrap_rework_count"
            + "&wrapped_at=gte.\(start)"
            + "&wrapped_at=lt.\(end)"
            + "&order=wrapped_at.asc"

        return try await supabaseGet(urlString)
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

        let itemsPerDay = Double(panels.count) / Double(period.workingDays)

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
            throw ReportingError.httpError(code)
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

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f
    }()

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
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .badURL:              return "Invalid Supabase URL configuration."
        case .httpError(let code): return "Server returned HTTP \(code)."
        }
    }
}
