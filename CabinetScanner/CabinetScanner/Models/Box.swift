import Foundation

struct Box: Identifiable, Codable, Hashable {
    let id: String
    let consignmentId: String
    let boxNumber: Int
    let boxType: BoxType
    let status: BoxStatus
    let itemCount: Int
    let createdAt: Date
    let closedAt: Date?

    enum BoxType: String, Codable, CaseIterable {
        case panel = "panel"
        case fittingKit = "fitting_kit"
        case drawerRunner = "drawer_runner"

        var displayName: String {
            switch self {
            case .panel: return "Panel Box"
            case .fittingKit: return "Fitting Kit Box"
            case .drawerRunner: return "Drawer Runner Box"
            }
        }

        var iconName: String {
            switch self {
            case .panel: return "shippingbox"
            case .fittingKit: return "wrench.and.screwdriver"
            case .drawerRunner: return "line.3.horizontal"
            }
        }

        var isManualEntry: Bool {
            self != .panel
        }
    }

    enum BoxStatus: String, Codable {
        case open
        case closed
    }

    var isOpen: Bool { status == .open }
    var isClosed: Bool { status == .closed }
}
