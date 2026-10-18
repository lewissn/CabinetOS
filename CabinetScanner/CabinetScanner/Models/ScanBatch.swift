import Foundation

// MARK: - Registry fetch (GET /manifests/:id/registry)

struct PanelRegistryResponse: Decodable {
    let ok: Bool
    let etag: String
    let notModified: Bool?
    let panels: [PanelRegistryEntry]
}

struct PanelRegistryEntry: Decodable {
    let panelUid: String
    let cabinetName: String
    let partNumber: String
    let lengthMm: Int
    let widthMm: Int
    let thicknessMm: Int
    let material: String
}

// MARK: - Packed panels mirror (GET /consignments/:id/packed-panels)

struct PackedPanelsResponse: Decodable {
    let ok: Bool
    let etag: String
    let panels: [PackedPanelEntry]
}

struct PackedPanelEntry: Decodable {
    let panelUid: String
    let boxId: String
    let scannedAt: String
}

// MARK: - Batch scan (POST /boxes/:id/scan-batch)

struct ScanBatchRequest: Encodable {
    let manifestId: String
    let consignmentId: String
    let scans: [ScanBatchItem]
}

struct ScanBatchItem: Encodable {
    let localId: String
    let projectName: String
    let cabinetName: String
    let partNumber: String
    let scannedAt: String
    let deviceId: String
    let stationId: String
    let operator_: String?

    enum CodingKeys: String, CodingKey {
        case localId, projectName, cabinetName, partNumber, scannedAt
        case deviceId, stationId
        case operator_ = "operator"
    }
}

struct ScanBatchResponse: Decodable {
    let ok: Bool
    let code: String?
    let reason: String?
    let message: String?
    let results: [ScanBatchItemResult]?
    let boxProgress: BoxProgress?

    struct BoxProgress: Decodable {
        let packedCount: Int
        let expectedCount: Int
    }
}

struct ScanBatchItemResult: Decodable {
    let localId: String
    let ok: Bool
    let code: String   // OK | NOT_ON_MANIFEST | ALREADY_PACKED | WRONG_CONSIGNMENT
    let boxItemId: String?
    let alreadyPackedInBoxId: String?
}
