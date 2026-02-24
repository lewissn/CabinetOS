import Foundation

final class DashboardService {

    // MARK: - Public

    func fetchSummary(days: Int = 7) async throws -> DashboardSummary {
        let cal = Calendar.london
        let now = Date()
        let todayStart = cal.startOfDay(for: now)

        guard let windowEnd = cal.date(byAdding: .day, value: days, to: todayStart),
              let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart),
              let tomorrowEnd = cal.date(byAdding: .day, value: 2, to: todayStart)
        else {
            return .empty
        }

        let rows = try await fetchJobs(before: windowEnd)

        var dueToday = 0
        var dueTomorrow = 0
        var overdue = 0
        var upcoming: [UpcomingJob] = []

        for row in rows {
            guard let dueDate = row.parsedDueDate else { continue }
            let dayStart = cal.startOfDay(for: dueDate)

            if dayStart < todayStart {
                overdue += 1
            }
            if dayStart >= todayStart && dayStart < tomorrowStart {
                dueToday += 1
            }
            if dayStart >= tomorrowStart && dayStart < tomorrowEnd {
                dueTomorrow += 1
            }

            let job = UpcomingJob(
                id: row.stableId,
                customer: row.customer ?? "Unknown",
                salesOrder: row.salesOrder ?? "—",
                shippingMethod: row.shippingMethod,
                dueDate: dueDate
            )
            upcoming.append(job)
        }

        upcoming.sort {
            if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
            return $0.customer.localizedCaseInsensitiveCompare($1.customer) == .orderedAscending
        }

        if upcoming.count > 30 {
            upcoming = Array(upcoming.prefix(30))
        }

        return DashboardSummary(
            dueToday: dueToday,
            dueTomorrow: dueTomorrow,
            overdue: overdue,
            upcoming: upcoming
        )
    }

    // MARK: - PostgREST fetch

    private func fetchJobs(before endDate: Date) async throws -> [JobRow] {
        let dateString = Self.isoDateFormatter.string(from: endDate)

        var components = URLComponents(string: Configuration.supabaseURL + "/rest/v1/jobs")!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,due_raw,customer,sales_order,shipping_method"),
            URLQueryItem(name: "due_raw", value: "lte.\(dateString)"),
            URLQueryItem(name: "order", value: "due_raw.asc,customer.asc"),
        ]

        guard let url = components.url else {
            throw DashboardError.badURL
        }

        var request = URLRequest(url: url)
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let http = response as? HTTPURLResponse
            throw DashboardError.httpError(http?.statusCode ?? -1)
        }

        return try JSONDecoder().decode([JobRow].self, from: data)
    }

    // MARK: - Date formatter

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}

// MARK: - Internal row model

private struct JobRow: Decodable {
    let id: Int?
    let dueRaw: String?
    let customer: String?
    let salesOrder: String?
    let shippingMethod: String?

    enum CodingKeys: String, CodingKey {
        case id
        case dueRaw = "due_raw"
        case customer
        case salesOrder = "sales_order"
        case shippingMethod = "shipping_method"
    }

    var parsedDueDate: Date? {
        guard let raw = dueRaw else { return nil }
        if let d = Self.dateOnly.date(from: raw) { return d }
        if let d = Self.iso8601Full.date(from: raw) { return d }
        if let d = Self.iso8601Fractional.date(from: raw) { return d }
        return nil
    }

    var stableId: String {
        if let id { return String(id) }
        return "\(customer ?? "")-\(salesOrder ?? "")-\(dueRaw ?? "")"
    }

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

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: - Errors

enum DashboardError: LocalizedError {
    case badURL
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid Supabase URL configuration."
        case .httpError(let code): return "Server returned HTTP \(code)."
        }
    }
}
