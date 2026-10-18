import SwiftUI
import Foundation

// ============================================================
// MARK: - ViewModel
// ============================================================

enum TileDetail: Identifiable {
    case dueToday
    case dueTomorrow
    case courierGroup(CourierGroup)

    var id: String {
        switch self {
        case .dueToday:              return "dueToday"
        case .dueTomorrow:           return "dueTomorrow"
        case .courierGroup(let g):   return "courier-\(g.shippingMethod)"
        }
    }

    var title: String {
        switch self {
        case .dueToday:              return "Due Today"
        case .dueTomorrow:           return "Due Tomorrow"
        case .courierGroup(let g):   return g.shippingMethod
        }
    }

    var accentColor: Color {
        switch self {
        case .dueToday:      return .blue
        case .dueTomorrow:   return .orange
        case .courierGroup:  return .blue
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
                result.append(GroupedSection(title: "Due Today", jobs: group.todayJobs.sorted { $0.customer < $1.customer }))
            }
            if !group.tomorrowJobs.isEmpty {
                result.append(GroupedSection(title: "Due Tomorrow", jobs: group.tomorrowJobs.sorted { $0.customer < $1.customer }))
            }
            return result
        }
    }

    private func groupedByMethod(_ jobs: [DispatchJob]) -> [GroupedSection] {
        let byMethod = Dictionary(grouping: jobs) { $0.shippingMethod }
        return byMethod
            .map { GroupedSection(title: $0.key, jobs: $0.value.sorted { $0.customer < $1.customer }) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
