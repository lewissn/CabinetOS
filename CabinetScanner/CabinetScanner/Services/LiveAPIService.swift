import Foundation

// MARK: - Live API Service
//
// Calls the Ops Next.js server (cabinet-lab2) at Configuration.apiBase.
// All paths are relative to /api/despatch/.
//
// Response mapping: Ops responses use snake_case JSON. Private OpsXxx structs
// mirror the exact Ops JSON shape, then map() to iOS model types. This keeps
// all ViewModels and Views unchanged regardless of Ops schema evolution.
//
// Endpoint table (all prefixed with /api/despatch):
//   GET  /manifests                          → fetchManifests
//   GET  /manifests/:id/consignments         → fetchConsignments
//   GET  /consignments/:id/boxes             → fetchBoxes          (NEW — added to Ops)
//   POST /consignments/:id/boxes/add-next    → createBox           (existing Ops route)
//   GET  /boxes/:id                          → fetchBoxDetail       (existing Ops route)
//   POST /boxes/:id/scan                     → scanItem            (NEW — added to Ops)
//   DELETE /boxes/:id                        → deleteBox           (existing Ops route)
//   POST /boxes/:id/close                    → closeBox            (NEW — added to Ops)
//   DELETE /panels/:id                       → deleteBoxItem       (existing Ops route, different path name)
//   POST /consignments/:id/finish            → finishConsignment   (NEW — added to Ops)

final class LiveAPIService: APIServiceProtocol {
    private let apiBase: String
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(apiBase: String = Configuration.apiBase) {
        self.apiBase = apiBase
        self.session = URLSession.shared

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Use explicit CodingKeys in private structs rather than automatic conversion,
        // so each mapping is obvious and survives Ops field renames.
        decoder.keyDecodingStrategy = .useDefaultKeys

        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .useDefaultKeys
    }

    // MARK: - Manifests

    func fetchManifests() async throws -> [Manifest] {
        let response: OpsManifestListResponse = try await get("/manifests")
        return response.manifests.map { $0.toManifest() }
    }

    // MARK: - Consignments

    func fetchConsignments(manifestId: String) async throws -> [Consignment] {
        let response: OpsConsignmentsResponse = try await get("/manifests/\(manifestId)/consignments")
        return response.consignments.map { $0.toConsignment(manifestId: manifestId) }
    }

    // MARK: - Boxes

    func fetchBoxes(consignmentId: String) async throws -> [Box] {
        let response: OpsBoxListResponse = try await get("/consignments/\(consignmentId)/boxes")
        return response.boxes.map { $0.toBox() }
    }

    func createBox(consignmentId: String, boxType: Box.BoxType) async throws -> Box {
        // add-next auto-generates the box label and increments box_number.
        // No need to supply a box_label_value from the iOS side.
        let body = OpsAddNextBoxRequest(type: boxType.rawValue)
        let response: OpsSingleBoxResponse = try await post(
            "/consignments/\(consignmentId)/boxes/add-next",
            body: body
        )
        return response.box.toBox()
    }

    func fetchBoxDetail(boxId: String) async throws -> (Box, [BoxItem]) {
        let response: OpsBoxDetailResponse = try await get("/boxes/\(boxId)")
        let box = response.box.toBox()
        let items = response.panels.map { $0.toBoxItem() }
        return (box, items)
    }

    func deleteBox(boxId: String) async throws {
        try await delete("/boxes/\(boxId)")
    }

    func closeBox(boxId: String) async throws -> Box {
        let response: OpsSingleBoxResponse = try await post("/boxes/\(boxId)/close", body: EmptyBody())
        return response.box.toBox()
    }

    func reopenBox(boxId: String, consignmentId: String) async throws {
        let body = ReopenBoxRequest(boxId: boxId)
        let _: OpsOkResponse = try await post("/consignments/\(consignmentId)/reopen-box", body: body)
    }

    // MARK: - Items

    func scanItem(boxId: String, request: ScanRequest) async throws -> ScanResponse {
        // The /boxes/:id/scan route returns the iOS ScanResponse shape directly.
        return try await post("/boxes/\(boxId)/scan", body: request)
    }

    func deleteBoxItem(boxItemId: String) async throws {
        // Ops route is DELETE /panels/:id (despatch_box_panels table).
        // The id from OpsPanel.toBoxItem() maps to despatch_box_panels.id — matches.
        try await delete("/panels/\(boxItemId)")
    }

    // MARK: - Finish Consignment

    func finishConsignment(consignmentId: String) async throws -> FinishConsignmentResponse {
        // The /consignments/:id/finish route returns the iOS FinishConsignmentResponse shape directly.
        return try await post("/consignments/\(consignmentId)/finish", body: EmptyBody())
    }

    // MARK: - HTTP helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: apiBase + path) else {
            throw APIError.invalidURL(apiBase + path)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        guard let url = URL(string: apiBase + path) else {
            throw APIError.invalidURL(apiBase + path)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func delete(_ path: String) async throws {
        guard let url = URL(string: apiBase + path) else {
            throw APIError.invalidURL(apiBase + path)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: req)
        try validateResponse(response, data: nil)
    }

    private func validateResponse(_ response: URLResponse, data: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            var serverMessage: String?
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                serverMessage = json["message"] as? String ?? json["error"] as? String
            }
            throw APIError.httpError(statusCode: http.statusCode, serverMessage: serverMessage)
        }
    }
}

// MARK: - Request body helpers

private struct EmptyBody: Encodable {}

private struct ReopenBoxRequest: Encodable {
    let boxId: String
}

private struct OpsOkResponse: Decodable {
    let ok: Bool
}

private struct OpsAddNextBoxRequest: Encodable {
    let type: String  // 'panel' | 'fitting_kit' | 'drawer_runner'
}

// MARK: - Ops response structs
// Each struct mirrors the actual Ops JSON shape. The toXxx() methods convert
// to iOS model types. Keeping this mapping here means ViewModels never see Ops types.

// GET /manifests → { ok, manifests: [...], total }
private struct OpsManifestListResponse: Decodable {
    let ok: Bool
    let manifests: [OpsManifest]
}

private struct OpsManifest: Decodable {
    let id: String
    let manifest_code: String      // displayed as the manifest "name" in iOS
    let status: String             // 'draft'|'ready_to_scan'|'scanning'|'finalized'|'completed'|'failed'
    let created_at: String

    func toManifest() -> Manifest {
        let date = ISO8601DateFormatter().date(from: created_at) ?? Date()
        let iosStatus: Manifest.ManifestStatus =
            (status == "completed" || status == "failed") ? .complete : .active
        return Manifest(
            id: id,
            name: manifest_code,
            createdAt: date,
            consignmentCount: 0,   // not returned by the list endpoint
            status: iosStatus
        )
    }
}

// GET /manifests/:id/consignments → { ok, consignments: [...] }
private struct OpsConsignmentsResponse: Decodable {
    let ok: Bool
    let consignments: [OpsConsignment]
}

private struct OpsConsignment: Decodable {
    let id: String
    let job_identifier: String     // = source_name = QR code value
    let status: String             // 'scanning' | 'completed' | 'cancelled'
    let expected_parts: Int?       // from packing_panel_registry count
    let packed_parts: Int?         // from despatch_box_panels count

    func toConsignment(manifestId: String) -> Consignment {
        let iosStatus: Consignment.ConsignmentStatus =
            (status == "completed") ? .complete : .open
        return Consignment(
            id: id,
            manifestId: manifestId,
            jobIdentifier: job_identifier,
            customerName: job_identifier,  // source_name is the canonical display name
            expectedItemCount: expected_parts ?? 0,
            packedItemCount: packed_parts ?? 0,
            status: iosStatus
        )
    }
}

// GET /consignments/:id/boxes → { ok, boxes: [...] }
private struct OpsBoxListResponse: Decodable {
    let ok: Bool
    let boxes: [OpsBox]
}

// POST /consignments/:id/boxes/add-next and POST /boxes/:id/close → { ok, box: ... }
private struct OpsSingleBoxResponse: Decodable {
    let ok: Bool
    let box: OpsBox
}

private struct OpsBox: Decodable {
    let id: String
    let consignment_id: String
    let box_number: Int?
    let box_type: String           // 'panel' | 'fitting_kit' | 'drawer_runner'
    let status: String?            // 'OPEN' | 'CLOSED' (uppercase in Ops DB)
    let item_count: Int?           // provided by GET /boxes endpoint
    let created_at: String
    let closed_at: String?

    func toBox() -> Box {
        let fmt = ISO8601DateFormatter()
        return Box(
            id: id,
            consignmentId: consignment_id,
            boxNumber: box_number ?? 1,
            boxType: Box.BoxType(rawValue: box_type) ?? .panel,
            status: (status == "CLOSED") ? .closed : .open,
            itemCount: item_count ?? 0,
            createdAt: fmt.date(from: created_at) ?? Date(),
            closedAt: closed_at.flatMap { fmt.date(from: $0) }
        )
    }
}

// GET /boxes/:id → { ok, box, panels: [...], totals }
private struct OpsBoxDetailResponse: Decodable {
    let ok: Bool
    let box: OpsBox
    let panels: [OpsPanel]
    // totals (volume/weight) are not used by iOS — ignored
}

private struct OpsPanel: Decodable {
    let id: String
    let box_id: String
    let panel_uid: String?
    let panel_value: String        // = "{source_name}|{cabinetName}|{partNumber}"
    let scanned_at: String

    func toBoxItem() -> BoxItem {
        // Parse the "|"-delimited UID into separate fields.
        // Format: "Lewis Nichols - 29248|LDC|4"
        // Note: source_name may itself contain "|" — but in practice never does.
        let raw = panel_uid ?? panel_value
        let parts = raw.split(separator: "|", maxSplits: 2).map(String.init)
        return BoxItem(
            id: id,
            boxId: box_id,
            projectName: parts.count > 0 ? parts[0] : raw,
            cabinetName: parts.count > 1 ? parts[1] : "?",
            partNumber:  parts.count > 2 ? parts[2] : "?",
            scannedAt: ISO8601DateFormatter().date(from: scanned_at) ?? Date(),
            deviceId: nil,     // not stored in despatch_box_panels
            operator_: nil     // not stored in despatch_box_panels
        )
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, serverMessage: String?)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):         return "Invalid URL: \(url)"
        case .invalidResponse:             return "Invalid server response"
        case .httpError(let code, let msg):
            if let msg { return "\(msg) (\(code))" }
            return "Server error (\(code))"
        case .decodingError(let err):      return "Data error: \(err.localizedDescription)"
        }
    }
}
