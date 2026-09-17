import Foundation

// MARK: - Manual Manifest

struct ManualManifest: Identifiable, Hashable {
    let id: String
    let manifestName: String
    let courier: String?
    let status: ManualManifestStatus
    let note: String?
    let createdAt: Date
    let updatedAt: Date

    enum ManualManifestStatus: String, Codable {
        case open
        case finished
    }

    var isFinished: Bool { status == .finished }
}

// MARK: - Manual Manifest Box

struct ManualManifestBox: Identifiable, Hashable {
    let id: String
    let manifestId: String
    let boxNumber: Int
    let status: BoxStatus
    let lengthMM: Int?
    let widthMM: Int?
    let heightMM: Int?
    let weightKG: Double?
    let createdAt: Date

    enum BoxStatus: String, Codable {
        case open
        case closed
    }

    var isOpen: Bool { status == .open }
    var isClosed: Bool { status == .closed }

    var dimensionsDisplay: String? {
        guard let l = lengthMM, let w = widthMM, let h = heightMM else { return nil }
        return "\(l)×\(w)×\(h) mm"
    }

    var weightDisplay: String? {
        guard let w = weightKG else { return nil }
        if w.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(w)) kg"
        }
        return String(format: "%.1f kg", w)
    }
}

// MARK: - Manual Manifest Item

struct ManualManifestItem: Identifiable, Hashable {
    let id: String
    let boxId: String
    let itemType: ItemType
    let projectName: String?
    let cabinetName: String?
    let partNumber: String?
    let manualItemName: String?
    let qty: Int
    let createdAt: Date

    enum ItemType: String, Codable {
        case label
        case manual
    }

    var isManual: Bool { itemType == .manual }

    var displayName: String {
        switch itemType {
        case .label:
            let cab = cabinetName ?? "?"
            let part = partNumber ?? "?"
            return "\(cab) — Part \(part)"
        case .manual:
            return manualItemName ?? "Unknown"
        }
    }

    var detailLine: String? {
        switch itemType {
        case .label:
            return projectName
        case .manual:
            return nil
        }
    }
}
