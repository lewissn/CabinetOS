import Foundation

struct BoxItem: Identifiable, Codable, Hashable {
    let id: String
    let boxId: String
    let projectName: String
    let cabinetName: String
    let partNumber: String
    let scannedAt: Date
    let deviceId: String?
    let operator_: String?

    enum CodingKeys: String, CodingKey {
        case id
        case boxId = "box_id"
        case projectName = "project_name"
        case cabinetName = "cabinet_name"
        case partNumber = "part_number"
        case scannedAt = "scanned_at"
        case deviceId = "device_id"
        case operator_ = "operator"
    }

    var displayLabel: String {
        "\(cabinetName) — Part \(partNumber)"
    }

    var fullLabel: String {
        "\(projectName) | \(cabinetName) | \(partNumber)"
    }
}

struct ManualBoxItem: Codable {
    let description: String
    let quantity: Int
}
