import Foundation

struct ScanTriplet: Equatable {
    let projectName: String
    let cabinetName: String
    let partNumber: String

    var displayString: String {
        "\(projectName) | \(cabinetName) | \(partNumber)"
    }
}

struct ScanResponse: Codable {
    let ok: Bool
    let added: AddedItem?
    let boxProgress: BoxProgress?
    let code: String?
    let message: String?
    let details: ScanErrorDetails?

    struct AddedItem: Codable {
        let boxItemId: String
        let projectName: String
        let cabinetName: String
        let partNumber: String
    }

    struct BoxProgress: Codable {
        let packedCount: Int
        let expectedCount: Int
    }

    struct ScanErrorDetails: Codable {
        let alreadyPackedInBoxId: String?
        let expectedProjectName: String?
        let expectedConsignmentId: String?
    }
}

struct FinishConsignmentResponse: Codable {
    let ok: Bool
    let missingItems: [MissingItem]?
    let message: String?

    struct MissingItem: Codable, Identifiable {
        let id: String?
        let projectName: String
        let cabinetName: String
        let partNumber: String

        var displayLabel: String {
            "\(cabinetName) — Part \(partNumber)"
        }

        // Use a computed id for Identifiable if server doesn't provide one
        var stableId: String {
            id ?? "\(projectName)|\(cabinetName)|\(partNumber)"
        }
    }
}
