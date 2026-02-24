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

        var isAutoClose: Bool {
            self != .panel
        }

        struct Dimensions {
            let lengthMM: Int
            let widthMM: Int
            let heightMM: Int
            let weightKG: Double

            var displaySize: String {
                "\(lengthMM) x \(widthMM) x \(heightMM) mm"
            }

            var displayWeight: String {
                weightKG.truncatingRemainder(dividingBy: 1) == 0
                    ? "\(Int(weightKG)) kg"
                    : String(format: "%.1f kg", weightKG)
            }
        }

        var fixedDimensions: Dimensions? {
            switch self {
            case .panel:
                return nil
            case .fittingKit:
                return Dimensions(lengthMM: 250, widthMM: 150, heightMM: 100, weightKG: 2)
            case .drawerRunner:
                return Dimensions(lengthMM: 400, widthMM: 200, heightMM: 200, weightKG: 5)
            }
        }
    }

    enum BoxStatus: String, Codable {
        case open
        case closed
    }

    var isOpen: Bool { status == .open }
    var isClosed: Bool { status == .closed }
}
