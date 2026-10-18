// The dashboard's data: what leaves today and tomorrow, grouped by courier,
// read straight from the Supabase jobs table. Moved out of DashboardView.swift
// unchanged in the design refresh; the query is as it was.

import Foundation

// ============================================================
// MARK: - Models
// ============================================================

struct DispatchIntelligence {
    let dueToday: Int
    let dueTomorrow: Int
    let courierGroups: [CourierGroup]
    let inHouseJobs: [DispatchJob]
    let todayJobs: [DispatchJob]
    let tomorrowJobs: [DispatchJob]

    static let empty = DispatchIntelligence(
        dueToday: 0, dueTomorrow: 0, courierGroups: [], inHouseJobs: [],
        todayJobs: [], tomorrowJobs: []
    )
}

struct CourierGroup: Identifiable {
    var id: String { shippingMethod }
    let shippingMethod: String
    let dueToday: Int
    let dueTomorrow: Int
    let todayJobs: [DispatchJob]
    let tomorrowJobs: [DispatchJob]

    var hasJobs: Bool { dueToday > 0 || dueTomorrow > 0 }
}

struct DispatchJob: Identifiable {
    let id: String
    let customer: String
    let salesOrder: String
    let postcode: String?
    let dueDate: Date
    let shippingMethod: String
    /// Where the job is, from the ShopVOX step on the jobs row.
    var stage: DispatchStage = .toPack
}

/// How far a job due out has got, read from ShopVOX's current step.
///
/// The jobs row keeps a job in the Post-Production group after Despatch is
/// completed, so without this a job despatched on Tuesday still counted as
/// due out on Friday. Every job due in the week of 12 Oct 2026 that the old
/// query returned was already "Despatch: completed".
enum DispatchStage: Int, Comparable {
    case toPack, packing, packed, despatched

    init(step: String?, status: String?) {
        let step = step ?? ""
        let status = (status ?? "").lowercased()
        switch step {
        case "Despatch":
            self = status == "completed" ? .despatched : .packed
        case "Fitting Kit Preparation":
            // Runs after Pack & Wrap: the panels are packed.
            self = .packed
        case "Pack & Wrap":
            switch status {
            case "completed": self = .packed
            case "started", "paused", "idling", "stopped": self = .packing
            default: self = .toPack
            }
        default:
            self = .toPack
        }
    }

    static func < (a: DispatchStage, b: DispatchStage) -> Bool { a.rawValue < b.rawValue }
}

extension Calendar {
    static let london: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/London")!
        return cal
    }()
}

// ============================================================
// MARK: - Service
// ============================================================

final class DashboardService {

    private static let inHouseKeywords = ["in-house", "in house", "inhouse"]

    static func isInHouse(_ method: String?) -> Bool {
        guard let method = method?.lowercased() else { return false }
        return inHouseKeywords.contains { method.contains($0) }
    }

    func fetchIntelligence() async throws -> DispatchIntelligence {
        let cal = Calendar.london
        let todayStart = cal.startOfDay(for: Date())

        guard let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart),
              let tomorrowEnd   = cal.date(byAdding: .day, value: 2, to: todayStart)
        else { return .empty }

        let rows = try await fetchJobs(from: todayStart, before: tomorrowEnd)

        var dueToday = 0
        var dueTomorrow = 0
        var methodTodayCounts: [String: Int] = [:]
        var methodTomorrowCounts: [String: Int] = [:]
        var methodTodayJobs: [String: [DispatchJob]] = [:]
        var methodTomorrowJobs: [String: [DispatchJob]] = [:]
        var allTodayJobs: [DispatchJob] = []
        var allTomorrowJobs: [DispatchJob] = []
        var inHouseJobs: [DispatchJob] = []

        for row in rows {
            guard let dueDate = row.parsedDueDate else { continue }
            let dayStart = cal.startOfDay(for: dueDate)

            let isToday    = dayStart >= todayStart && dayStart < tomorrowStart
            let isTomorrow = dayStart >= tomorrowStart && dayStart < tomorrowEnd

            let method = row.shippingMethod ?? "Other"

            let job = DispatchJob(
                id: row.stableId,
                customer: row.customer ?? "Unknown",
                salesOrder: row.salesOrderString ?? "—",
                postcode: row.postcode,
                dueDate: dueDate,
                shippingMethod: method,
                stage: DispatchStage(step: row.workflowStep, status: row.workflowStatus)
            )

            if isToday {
                dueToday += 1
                methodTodayCounts[method, default: 0] += 1
                methodTodayJobs[method, default: []].append(job)
                allTodayJobs.append(job)
            }

            if isTomorrow {
                dueTomorrow += 1
                methodTomorrowCounts[method, default: 0] += 1
                methodTomorrowJobs[method, default: []].append(job)
                allTomorrowJobs.append(job)
            }

            if Self.isInHouse(row.shippingMethod) && (isToday || isTomorrow) {
                inHouseJobs.append(job)
            }
        }

        let allMethods = Set(methodTodayCounts.keys).union(methodTomorrowCounts.keys)
        let courierGroups = allMethods
            .map { method in
                CourierGroup(
                    shippingMethod: method,
                    dueToday: methodTodayCounts[method] ?? 0,
                    dueTomorrow: methodTomorrowCounts[method] ?? 0,
                    todayJobs: methodTodayJobs[method] ?? [],
                    tomorrowJobs: methodTomorrowJobs[method] ?? []
                )
            }
            .filter { $0.hasJobs }
            .sorted {
                $0.shippingMethod.localizedCaseInsensitiveCompare($1.shippingMethod) == .orderedAscending
            }

        inHouseJobs.sort { a, b in
            switch (a.postcode?.nilIfEmpty, b.postcode?.nilIfEmpty) {
            case (nil, nil):   return a.customer < b.customer
            case (nil, _):     return false
            case (_, nil):     return true
            case let (pa?, pb?): return pa.localizedCaseInsensitiveCompare(pb) == .orderedAscending
            }
        }

        return DispatchIntelligence(
            dueToday: dueToday,
            dueTomorrow: dueTomorrow,
            courierGroups: courierGroups,
            inHouseJobs: inHouseJobs,
            todayJobs: allTodayJobs,
            tomorrowJobs: allTomorrowJobs
        )
    }

    // MARK: PostgREST

    private func fetchJobs(from startDate: Date, before endDate: Date) async throws -> [JobRow] {
        let startString = Self.isoDateFormatter.string(from: startDate)
        let endString   = Self.isoDateFormatter.string(from: endDate)

        let urlString = Configuration.supabaseURL + "/rest/v1/jobs"
            + "?select=id,due_raw,customer,sales_order,shipping_method,workflow_step,workflow_status"
            + "&due_raw=gte.\(startString)"
            + "&due_raw=lt.\(endString)"
            + "&workflow_group=in.(Post-Production,Production)"
            + "&order=due_raw.asc,customer.asc"

        guard let url = URL(string: urlString) else { throw DashboardError.badURL }

        var request = URLRequest(url: url)
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let http = response as? HTTPURLResponse
            throw DashboardError.httpError(http?.statusCode ?? -1)
        }

        do {
            return try JSONDecoder().decode([JobRow].self, from: data)
        } catch {
            #if DEBUG
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            print("[DashboardService] Decode failed: \(error)")
            print("[DashboardService] Response preview: \(preview)")
            #endif
            throw error
        }
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}

// MARK: - Decodable row

private struct JobRow: Decodable {
    let id: FlexibleID?
    let dueRaw: String?
    let customer: String?
    let salesOrder: FlexibleString?
    let shippingMethod: String?
    let postcode: String?
    let workflowStep: String?
    let workflowStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case dueRaw        = "due_raw"
        case customer
        case salesOrder     = "sales_order"
        case shippingMethod = "shipping_method"
        case postcode
        case workflowStep   = "workflow_step"
        case workflowStatus = "workflow_status"
    }

    var parsedDueDate: Date? {
        guard let raw = dueRaw else { return nil }
        if let d = Self.dateOnly.date(from: raw) { return d }
        if let d = Self.iso8601Full.date(from: raw) { return d }
        return nil
    }

    var stableId: String {
        if let id { return id.stringValue }
        return "\(customer ?? "")-\(salesOrder?.stringValue ?? "")-\(dueRaw ?? "")"
    }

    var salesOrderString: String? { salesOrder?.stringValue }

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f
    }()

    private static let iso8601Full: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

/// Decodes a JSON value that may be an Int, String, or UUID.
private enum FlexibleID: Decodable {
    case int(Int)
    case string(String)

    var stringValue: String {
        switch self {
        case .int(let v):    return String(v)
        case .string(let v): return v
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Int.self)    { self = .int(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        throw DecodingError.typeMismatch(
            FlexibleID.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Expected Int or String")
        )
    }
}

/// Decodes a value that may arrive as a String or a Number.
private enum FlexibleString: Decodable {
    case string(String)
    case number(Double)

    var stringValue: String {
        switch self {
        case .string(let v): return v
        case .number(let v):
            if v == v.rounded() { return String(Int(v)) }
            return String(v)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        throw DecodingError.typeMismatch(
            FlexibleString.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Expected String or Number")
        )
    }
}

enum DashboardError: LocalizedError {
    case badURL
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .badURL:             return "Invalid Supabase URL configuration."
        case .httpError(let code): return "Server returned HTTP \(code)."
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
