import Foundation

// MARK: - APC Deadline Service
//
// Queries the Supabase `jobs` table for APC shipments due today
// that are still in a pre-dispatch workflow group.

final class APCDeadlineService {

    func fetchAPCJobsDueToday() async throws -> [APCDeadlineJob] {
        let todayString = Self.isoDateFormatter.string(from: Date())

        let urlString = Configuration.supabaseURL + "/rest/v1/jobs"
            + "?select=id,due_raw,customer,sales_order,shipping_method"
            + "&shipping_method=ilike.*apc*"
            + "&due_raw=eq.\(todayString)"
            + "&workflow_group=in.(\(DashboardService.committedGroups))"
            + "&order=customer.asc"

        guard let url = URL(string: urlString) else {
            throw APCDeadlineError.badURL
        }

        var request = URLRequest(url: url)
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APCDeadlineError.httpError(code)
        }

        let rows = try JSONDecoder().decode([APCJobRow].self, from: data)
        return rows.compactMap { $0.toAPCDeadlineJob() }
    }

    // MARK: - Formatters

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        // London, not the default UTC. In summer time London's midnight is
        // 23:00 UTC the day before, so the query asked for yesterday and
        // today and never fetched tomorrow's jobs.
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f
    }()
}

// MARK: - Decodable row

private struct APCJobRow: Decodable {
    let id: APCFlexibleID?
    let dueRaw: String?
    let customer: String?
    let salesOrder: APCFlexibleValue?
    let shippingMethod: String?

    enum CodingKeys: String, CodingKey {
        case id
        case dueRaw = "due_raw"
        case customer
        case salesOrder = "sales_order"
        case shippingMethod = "shipping_method"
    }

    func toAPCDeadlineJob() -> APCDeadlineJob? {
        let dueDate: Date
        if let raw = dueRaw {
            if let d = Self.dateOnly.date(from: raw) { dueDate = d }
            else if let d = Self.iso8601Full.date(from: raw) { dueDate = d }
            else { return nil }
        } else {
            return nil
        }

        return APCDeadlineJob(
            id: id?.stringValue ?? UUID().uuidString,
            customer: customer ?? "Unknown",
            salesOrder: salesOrder?.stringValue ?? "—",
            shippingMethod: shippingMethod ?? "APC",
            dueDate: dueDate
        )
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
}

// MARK: - Flexible decoders (JSON value may be Int, String, or Number)

private enum APCFlexibleID: Decodable {
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
            APCFlexibleID.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Expected Int or String")
        )
    }
}

private enum APCFlexibleValue: Decodable {
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
            APCFlexibleValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Expected String or Number")
        )
    }
}

// MARK: - Errors

enum APCDeadlineError: LocalizedError {
    case badURL
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .badURL:              return "Invalid Supabase URL configuration."
        case .httpError(let code): return "Server returned HTTP \(code)."
        }
    }
}
