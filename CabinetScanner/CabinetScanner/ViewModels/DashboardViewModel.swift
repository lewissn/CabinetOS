import SwiftUI
import Foundation

// ============================================================
// MARK: - ViewModel
// ============================================================

enum TileDetail: Identifiable {
    case dueToday
    case dueTomorrow
    case courierGroup(CourierGroup)
    case day(DayLoad)

    var id: String {
        switch self {
        case .dueToday:              return "dueToday"
        case .dueTomorrow:           return "dueTomorrow"
        case .courierGroup(let g):   return "courier-\(g.shippingMethod)"
        case .day(let d):            return "day-\(d.date.timeIntervalSince1970)"
        }
    }

    var title: String {
        switch self {
        case .dueToday:              return "Due Today"
        case .dueTomorrow:           return WorkingDay.dueLabel()
        case .courierGroup(let g):   return g.shippingMethod
        case .day:                   return "Due"
        }
    }

    var accentColor: Color {
        switch self {
        case .dueToday:      return .blue
        case .dueTomorrow:   return .orange
        case .courierGroup:  return .blue
        case .day:           return .blue
        }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case loaded
        case error(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var intelligence: DispatchIntelligence = .empty
    @Published var selectedTile: TileDetail?

    private let service = DashboardService()
    private let cache = SameDayCache<DispatchIntelligence>(name: "dispatch")
    /// When the figures on screen were fetched, if they came from the device.
    private(set) var cachedAt: Date?

    init() {
        // Open on the last figures from today, then refresh over them.
        if let cached = cache.load() {
            intelligence = cached.value
            cachedAt = cached.savedAt
            state = .loaded
        }
    }

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
            cache.save(intelligence)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    struct GroupedSection: Identifiable {
        var id: String { title }
        let title: String
        let jobs: [DispatchJob]
    }

    func sections(for detail: TileDetail) -> [GroupedSection] {
        switch detail {
        case .dueToday:
            return groupedByMethod(intelligence.todayJobs)

        case .dueTomorrow:
            return groupedByMethod(intelligence.tomorrowJobs)

        case .courierGroup(let group):
            var result: [GroupedSection] = []
            if !group.todayJobs.isEmpty {
                result.append(GroupedSection(title: "Due Today", jobs: group.todayJobs.sorted { ($0.stage, $0.customer) < ($1.stage, $1.customer) }))
            }
            if !group.tomorrowJobs.isEmpty {
                result.append(GroupedSection(title: WorkingDay.dueLabel(), jobs: group.tomorrowJobs.sorted { ($0.stage, $0.customer) < ($1.stage, $1.customer) }))
            }
            return result

        case .day(let day):
            return groupedByMethod(day.jobs)
        }
    }

    private func groupedByMethod(_ jobs: [DispatchJob]) -> [GroupedSection] {
        let byMethod = Dictionary(grouping: jobs) { $0.shippingMethod }
        return byMethod
            .map { GroupedSection(title: $0.key, jobs: $0.value.sorted { ($0.stage, $0.customer) < ($1.stage, $1.customer) }) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
