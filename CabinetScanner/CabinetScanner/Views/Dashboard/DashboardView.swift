import SwiftUI
import Foundation

// ============================================================
// MARK: - Models
// ============================================================

struct DashboardSummary {
    let dueToday: Int
    let dueTomorrow: Int
    let upcoming: [UpcomingJob]

    static let empty = DashboardSummary(dueToday: 0, dueTomorrow: 0, upcoming: [])
}

struct UpcomingJob: Identifiable {
    let id: String
    let customer: String
    let salesOrder: String
    let shippingMethod: String?
    let dueDate: Date

    var isDueToday: Bool {
        Calendar.london.isDateInToday(dueDate)
    }
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

    func fetchSummary() async throws -> DashboardSummary {
        let cal = Calendar.london
        let todayStart = cal.startOfDay(for: Date())

        guard let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart),
              let tomorrowEnd = cal.date(byAdding: .day, value: 2, to: todayStart),
              let windowEnd = cal.date(byAdding: .day, value: 3, to: todayStart)
        else {
            return .empty
        }

        let rows = try await fetchJobs(from: todayStart, before: windowEnd)

        var dueToday = 0
        var dueTomorrow = 0
        var upcoming: [UpcomingJob] = []

        for row in rows {
            guard let dueDate = row.parsedDueDate else { continue }
            let dayStart = cal.startOfDay(for: dueDate)

            if dayStart < todayStart { continue }
            if dayStart >= todayStart && dayStart < tomorrowStart { dueToday += 1 }
            if dayStart >= tomorrowStart && dayStart < tomorrowEnd { dueTomorrow += 1 }

            upcoming.append(UpcomingJob(
                id: row.stableId,
                customer: row.customer ?? "Unknown",
                salesOrder: row.salesOrderString ?? "—",
                shippingMethod: row.shippingMethod,
                dueDate: dueDate
            ))
        }

        upcoming.sort {
            if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
            return $0.customer.localizedCaseInsensitiveCompare($1.customer) == .orderedAscending
        }

        if upcoming.count > 30 { upcoming = Array(upcoming.prefix(30)) }

        return DashboardSummary(
            dueToday: dueToday,
            dueTomorrow: dueTomorrow,
            upcoming: upcoming
        )
    }

    // MARK: PostgREST

    private func fetchJobs(from startDate: Date, before endDate: Date) async throws -> [JobRow] {
        let startString = Self.isoDateFormatter.string(from: startDate)
        let endString = Self.isoDateFormatter.string(from: endDate)

        var components = URLComponents(string: Configuration.supabaseURL + "/rest/v1/jobs")!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,due_raw,customer,sales_order,shipping_method"),
            URLQueryItem(name: "due_raw", value: "gte.\(startString)"),
            URLQueryItem(name: "due_raw", value: "lt.\(endString)"),
            URLQueryItem(name: "order", value: "due_raw.asc,customer.asc"),
        ]

        guard let url = components.url else { throw DashboardError.badURL }

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

private struct JobRow: Decodable {
    let id: FlexibleID?
    let dueRaw: String?
    let customer: String?
    let salesOrder: FlexibleString?
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
        case .int(let v): return String(v)
        case .string(let v): return v
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Int.self) { self = .int(v); return }
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
        case .badURL: return "Invalid Supabase URL configuration."
        case .httpError(let code): return "Server returned HTTP \(code)."
        }
    }
}

// ============================================================
// MARK: - ViewModel
// ============================================================

@MainActor
final class DashboardViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded
        case error(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var summary: DashboardSummary = .empty

    private let service = DashboardService()

    var greeting: String {
        let hour = Calendar.london.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        f.timeZone = TimeZone(identifier: "Europe/London")
        return f.string(from: Date())
    }

    func refresh() async {
        if case .loading = state {} else { state = .loading }
        do {
            summary = try await service.fetchSummary()
            state = .loaded
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

// ============================================================
// MARK: - Dashboard View
// ============================================================

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statsRow
                    upcomingSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await vm.refresh() }
            .task { await vm.refresh() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.greeting)
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(vm.formattedDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image("CabinetLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
        }
        .padding(.top, 16)
    }

    // MARK: Stats cards

    private var statsRow: some View {
        HStack(spacing: 12) {
            if vm.state == .loading {
                skeletonCard
                skeletonCard
            } else {
                StatCard(title: "Due Today", value: vm.summary.dueToday, subtitle: "Jobs", accentColor: .blue)
                StatCard(title: "Due Tomorrow", value: vm.summary.dueTomorrow, subtitle: "Jobs", accentColor: .orange)
            }
        }
    }

    // MARK: Upcoming list

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Dispatches")
                .font(.title3)
                .fontWeight(.semibold)

            if vm.state == .loading {
                ForEach(0..<4, id: \.self) { _ in skeletonRow }
            } else if case .error(let msg) = vm.state {
                errorCard(msg)
            } else if vm.summary.upcoming.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.summary.upcoming) { job in
                        UpcomingJobRow(job: job)
                        if job.id != vm.summary.upcoming.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
            }
        }
    }

    // MARK: States

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("Nothing due in the next 3 days.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") { Task { await vm.refresh() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Skeletons

    private var skeletonCard: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.quaternary)
            .frame(maxWidth: .infinity)
            .frame(height: 100)
    }

    private var skeletonRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 140, height: 14)
                RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 100, height: 12)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 40, height: 12)
        }
        .padding(.vertical, 10)
    }
}

// ============================================================
// MARK: - Stat Card component
// ============================================================

private struct StatCard: View {
    let title: String
    let value: Int
    let subtitle: String
    var accentColor: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }
}

// ============================================================
// MARK: - Upcoming Job Row component
// ============================================================

private struct UpcomingJobRow: View {
    let job: UpcomingJob

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.customer)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                secondaryLine
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if job.isDueToday {
                badge("Today", color: .blue)
            } else {
                Text(formattedDueDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var secondaryLine: some View {
        let parts = [
            "SO \(job.salesOrder)",
            job.shippingMethod
        ].compactMap { $0 }

        Text(parts.joined(separator: " \u{2022} "))
    }

    private var formattedDueDate: String {
        let cal = Calendar.london
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/London")

        if cal.isDate(job.dueDate, equalTo: Date(), toGranularity: .weekOfYear) {
            f.dateFormat = "EEE"
        } else {
            f.dateFormat = "d MMM"
        }
        return f.string(from: job.dueDate)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}
