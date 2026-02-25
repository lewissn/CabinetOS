import SwiftUI
import Foundation

// ============================================================
// MARK: - Models
// ============================================================

struct DispatchIntelligence {
    let dueToday: Int
    let dueTomorrow: Int
    let courierGroups: [CourierGroup]
    let inHouseJobs: [DispatchJob]

    static let empty = DispatchIntelligence(
        dueToday: 0, dueTomorrow: 0, courierGroups: [], inHouseJobs: []
    )
}

struct CourierGroup: Identifiable {
    var id: String { shippingMethod }
    let shippingMethod: String
    let dueToday: Int
    let dueTomorrow: Int

    var hasJobs: Bool { dueToday > 0 || dueTomorrow > 0 }
}

struct DispatchJob: Identifiable {
    let id: String
    let customer: String
    let salesOrder: String
    let postcode: String?
    let dueDate: Date
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
        var inHouseJobs: [DispatchJob] = []

        for row in rows {
            guard let dueDate = row.parsedDueDate else { continue }
            let dayStart = cal.startOfDay(for: dueDate)

            let isToday    = dayStart >= todayStart && dayStart < tomorrowStart
            let isTomorrow = dayStart >= tomorrowStart && dayStart < tomorrowEnd

            if isToday    { dueToday += 1 }
            if isTomorrow { dueTomorrow += 1 }

            let method = row.shippingMethod ?? "Other"

            if isToday    { methodTodayCounts[method, default: 0] += 1 }
            if isTomorrow { methodTomorrowCounts[method, default: 0] += 1 }

            if Self.isInHouse(row.shippingMethod) && (isToday || isTomorrow) {
                inHouseJobs.append(DispatchJob(
                    id: row.stableId,
                    customer: row.customer ?? "Unknown",
                    salesOrder: row.salesOrderString ?? "—",
                    postcode: row.postcode,
                    dueDate: dueDate
                ))
            }
        }

        let allMethods = Set(methodTodayCounts.keys).union(methodTomorrowCounts.keys)
        let courierGroups = allMethods
            .map { method in
                CourierGroup(
                    shippingMethod: method,
                    dueToday: methodTodayCounts[method] ?? 0,
                    dueTomorrow: methodTomorrowCounts[method] ?? 0
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
            inHouseJobs: inHouseJobs
        )
    }

    // MARK: PostgREST

    private func fetchJobs(from startDate: Date, before endDate: Date) async throws -> [JobRow] {
        let startString = Self.isoDateFormatter.string(from: startDate)
        let endString   = Self.isoDateFormatter.string(from: endDate)

        var components = URLComponents(string: Configuration.supabaseURL + "/rest/v1/jobs")!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,due_raw,customer,sales_order,shipping_method,postcode"),
            URLQueryItem(name: "due_raw", value: "gte.\(startString)"),
            URLQueryItem(name: "due_raw", value: "lt.\(endString)"),
            URLQueryItem(name: "workflow_group", value: "in.(Post-Production,Production)"),
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

// MARK: - Decodable row

private struct JobRow: Decodable {
    let id: FlexibleID?
    let dueRaw: String?
    let customer: String?
    let salesOrder: FlexibleString?
    let shippingMethod: String?
    let postcode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case dueRaw        = "due_raw"
        case customer
        case salesOrder     = "sales_order"
        case shippingMethod = "shipping_method"
        case postcode
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
    @Published private(set) var intelligence: DispatchIntelligence = .empty

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
            intelligence = try await service.fetchIntelligence()
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
    var switchToPackaging: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statsRow
                    courierSummarySection
                    inHouseLoadingSection
                    packagingShortcut
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
                .offset(y: -2)
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
                StatCard(title: "Due Today",
                         value: vm.intelligence.dueToday,
                         subtitle: "Jobs",
                         accentColor: .blue)
                StatCard(title: "Due Tomorrow",
                         value: vm.intelligence.dueTomorrow,
                         subtitle: "Jobs",
                         accentColor: .orange)
            }
        }
    }

    // MARK: Courier summary

    private var courierSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dispatch Intelligence", systemImage: "shippingbox")
                .font(.title3)
                .fontWeight(.semibold)

            if vm.state == .loading {
                ForEach(0..<3, id: \.self) { _ in skeletonRow }
            } else if case .error(let msg) = vm.state {
                errorCard(msg)
            } else if vm.intelligence.courierGroups.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.intelligence.courierGroups) { group in
                        CourierGroupRow(group: group)
                        if group.id != vm.intelligence.courierGroups.last?.id {
                            Divider().padding(.leading, 4)
                        }
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
            }
        }
    }

    // MARK: In-house loading order

    @ViewBuilder
    private var inHouseLoadingSection: some View {
        if vm.state == .loaded && !vm.intelligence.inHouseJobs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("In-House Loading Order", systemImage: "truck.box")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Load last drop first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(spacing: 0) {
                    ForEach(Array(vm.intelligence.inHouseJobs.enumerated()),
                            id: \.element.id) { index, job in
                        InHouseJobRow(job: job, position: index + 1)
                        if index < vm.intelligence.inHouseJobs.count - 1 {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
            }
        }
    }

    // MARK: Packaging shortcut

    private var packagingShortcut: some View {
        Button(action: switchToPackaging) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.blue)
                Text("Open Packaging")
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: States

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("No dispatches due.")
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
// MARK: - Stat Card
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
// MARK: - Courier Group Row
// ============================================================

private struct CourierGroupRow: View {
    let group: CourierGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.shippingMethod)
                .font(.body)
                .fontWeight(.semibold)

            if group.dueToday > 0 {
                HStack(spacing: 6) {
                    Circle().fill(.blue).frame(width: 6, height: 6)
                    Text("Jobs due today: \(group.dueToday)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if group.dueTomorrow > 0 {
                HStack(spacing: 6) {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                    Text("Jobs due tomorrow: \(group.dueTomorrow)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

// ============================================================
// MARK: - In-House Job Row
// ============================================================

private struct InHouseJobRow: View {
    let job: DispatchJob
    let position: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("\(position)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(job.customer)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("SO \(job.salesOrder)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let postcode = job.postcode, !postcode.isEmpty {
                Text(postcode)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1), in: Capsule())
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 6)
    }
}
