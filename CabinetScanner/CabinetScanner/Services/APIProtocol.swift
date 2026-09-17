import Foundation

protocol APIServiceProtocol {
    // Manifests
    func fetchManifests() async throws -> [Manifest]

    // Consignments
    func fetchConsignments(manifestId: String) async throws -> [Consignment]

    // Boxes
    func fetchBoxes(consignmentId: String) async throws -> [Box]
    func createBox(consignmentId: String, boxType: Box.BoxType) async throws -> Box
    func fetchBoxDetail(boxId: String) async throws -> (Box, [BoxItem])
    func deleteBox(boxId: String) async throws
    func closeBox(boxId: String, wrappedBy: String?, wrappedByDevice: String?) async throws -> Box
    func reopenBox(boxId: String, consignmentId: String, reopenedByDevice: String?) async throws

    // Items
    func scanItem(boxId: String, request: ScanRequest) async throws -> ScanResponse
    func deleteBoxItem(boxItemId: String) async throws

    // Finish
    func finishConsignment(consignmentId: String) async throws -> FinishConsignmentResponse

    // Offline-capable scanning support
    func fetchPanelRegistry(manifestId: String, projectName: String, etag: String?) async throws -> PanelRegistryResponse
    func fetchPackedPanels(consignmentId: String) async throws -> PackedPanelsResponse
    func submitScanBatch(boxId: String, request: ScanBatchRequest) async throws -> ScanBatchResponse
}

struct ScanRequest: Codable {
    let manifestId: String
    let consignmentId: String
    let projectName: String
    let cabinetName: String
    let partNumber: String
    let deviceId: String
    let stationId: String
    let operator_: String?
    let scannedAt: String

    enum CodingKeys: String, CodingKey {
        case manifestId
        case consignmentId
        case projectName
        case cabinetName
        case partNumber
        case deviceId
        case stationId
        case operator_ = "operator"
        case scannedAt
    }
}
