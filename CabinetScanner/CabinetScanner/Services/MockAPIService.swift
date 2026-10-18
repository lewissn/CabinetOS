import Foundation

final class MockAPIService: APIServiceProtocol {
    // In-memory mock state
    private var manifests: [Manifest] = MockData.manifests
    private var consignments: [String: [Consignment]] = MockData.consignments
    private var boxes: [String: [Box]] = [:]
    private var boxItems: [String: [BoxItem]] = [:]
    private var nextBoxNumber: [String: Int] = [:]
    private var packedTriplets: Set<String> = []

    init() {
        // Pre-seed some boxes for the first consignment
        let consId = "cons-001"
        let box = Box(
            id: "box-001",
            consignmentId: consId,
            boxNumber: 1,
            boxType: .panel,
            status: .open,
            itemCount: 0,
            createdAt: Date(),
            closedAt: nil,
            wrappedAt: nil,
            wrappedBy: nil,
            wrappedByDevice: nil,
            wrapReworkCount: 0
        )
        boxes[consId] = [box]
        boxItems["box-001"] = []
        nextBoxNumber[consId] = 2
    }

    // MARK: - Manifests

    func fetchManifests() async throws -> [Manifest] {
        try await simulateDelay()
        return manifests
    }

    // MARK: - Consignments

    func fetchConsignments(manifestId: String) async throws -> [Consignment] {
        try await simulateDelay()
        return consignments[manifestId] ?? []
    }

    // MARK: - Boxes

    func fetchBoxes(consignmentId: String) async throws -> [Box] {
        try await simulateDelay()
        return boxes[consignmentId] ?? []
    }

    func createBox(consignmentId: String, boxType: Box.BoxType) async throws -> Box {
        try await simulateDelay()
        let num = nextBoxNumber[consignmentId, default: 1]
        nextBoxNumber[consignmentId] = num + 1

        let box = Box(
            id: UUID().uuidString,
            consignmentId: consignmentId,
            boxNumber: num,
            boxType: boxType,
            status: .open,
            itemCount: 0,
            createdAt: Date(),
            closedAt: nil,
            wrappedAt: nil,
            wrappedBy: nil,
            wrappedByDevice: nil,
            wrapReworkCount: 0
        )
        boxes[consignmentId, default: []].append(box)
        boxItems[box.id] = []
        return box
    }

    func fetchBoxDetail(boxId: String) async throws -> (Box, [BoxItem]) {
        try await simulateDelay()
        guard let box = findBox(boxId) else {
            throw APIError.httpError(statusCode: 404, serverMessage: nil)
        }
        let items = boxItems[boxId] ?? []
        return (box, items)
    }

    func deleteBox(boxId: String) async throws {
        try await simulateDelay()
        // Remove packed triplets for items in this box
        for item in (boxItems[boxId] ?? []) {
            packedTriplets.remove(tripletKey(item.projectName, item.cabinetName, item.partNumber))
        }
        boxItems.removeValue(forKey: boxId)
        for key in boxes.keys {
            boxes[key]?.removeAll { $0.id == boxId }
        }
    }

    func closeBox(boxId: String, wrappedBy: String?, wrappedByDevice: String?) async throws -> Box {
        try await simulateDelay()
        guard let box = findBox(boxId) else {
            throw APIError.httpError(statusCode: 404, serverMessage: nil)
        }
        let closed = Box(
            id: box.id,
            consignmentId: box.consignmentId,
            boxNumber: box.boxNumber,
            boxType: box.boxType,
            status: .closed,
            itemCount: boxItems[boxId]?.count ?? 0,
            createdAt: box.createdAt,
            closedAt: Date(),
            wrappedAt: Date(),
            wrappedBy: wrappedBy?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? wrappedBy : nil,
            wrappedByDevice: wrappedByDevice,
            wrapReworkCount: box.wrapReworkCount
        )
        replaceBox(closed)
        return closed
    }

    func reopenBox(boxId: String, consignmentId: String, reopenedByDevice: String?) async throws {
        try await simulateDelay()
        guard let box = findBox(boxId) else {
            throw APIError.httpError(statusCode: 404, serverMessage: nil)
        }
        let isSelfCorrection = reopenedByDevice != nil && reopenedByDevice == box.wrappedByDevice
        let countsAsRework = box.wrappedAt != nil && !isSelfCorrection
        let reopened = Box(
            id: box.id,
            consignmentId: box.consignmentId,
            boxNumber: box.boxNumber,
            boxType: box.boxType,
            status: .open,
            itemCount: boxItems[boxId]?.count ?? 0,
            createdAt: box.createdAt,
            closedAt: nil,
            wrappedAt: nil,
            wrappedBy: nil,
            wrappedByDevice: nil,
            wrapReworkCount: box.wrapReworkCount + (countsAsRework ? 1 : 0)
        )
        replaceBox(reopened)
    }

    // MARK: - Items

    func scanItem(boxId: String, request: ScanRequest) async throws -> ScanResponse {
        try await simulateDelay()

        guard let box = findBox(boxId) else {
            return ScanResponse(
                ok: false, added: nil, boxProgress: nil,
                code: "BOX_NOT_FOUND", message: "Box not found",
                details: nil
            )
        }

        // Check if the consignment matches
        if box.consignmentId != request.consignmentId {
            return ScanResponse(
                ok: false, added: nil, boxProgress: nil,
                code: "WRONG_CONSIGNMENT",
                message: "This item belongs to a different consignment",
                details: ScanResponse.ScanErrorDetails(
                    alreadyPackedInBoxId: nil,
                    expectedProjectName: nil,
                    expectedConsignmentId: box.consignmentId
                )
            )
        }

        let key = tripletKey(request.projectName, request.cabinetName, request.partNumber)
        if packedTriplets.contains(key) {
            return ScanResponse(
                ok: false, added: nil, boxProgress: nil,
                code: "ALREADY_PACKED",
                message: "This part has already been packed",
                details: nil
            )
        }

        // Validate against manifest items (simplified: always accept in mock)
        let item = BoxItem(
            id: UUID().uuidString,
            boxId: boxId,
            projectName: request.projectName,
            cabinetName: request.cabinetName,
            partNumber: request.partNumber,
            scannedAt: Date(),
            deviceId: request.deviceId,
            operator_: request.operator_
        )
        boxItems[boxId, default: []].append(item)
        packedTriplets.insert(key)

        // Update box item count
        if let box = findBox(boxId) {
            let updated = Box(
                id: box.id,
                consignmentId: box.consignmentId,
                boxNumber: box.boxNumber,
                boxType: box.boxType,
                status: box.status,
                itemCount: boxItems[boxId]?.count ?? 0,
                createdAt: box.createdAt,
                closedAt: box.closedAt,
                wrappedAt: box.wrappedAt,
                wrappedBy: box.wrappedBy,
                wrappedByDevice: box.wrappedByDevice,
                wrapReworkCount: box.wrapReworkCount
            )
            replaceBox(updated)
        }

        let totalPacked = boxes[request.consignmentId]?
            .reduce(0) { $0 + (boxItems[$1.id]?.count ?? 0) } ?? 0

        return ScanResponse(
            ok: true,
            added: ScanResponse.AddedItem(
                boxItemId: item.id,
                projectName: item.projectName,
                cabinetName: item.cabinetName,
                partNumber: item.partNumber
            ),
            boxProgress: ScanResponse.BoxProgress(
                packedCount: totalPacked,
                expectedCount: 24
            ),
            code: nil, message: nil, details: nil
        )
    }

    func deleteBoxItem(boxItemId: String) async throws {
        try await simulateDelay()
        for key in boxItems.keys {
            if let idx = boxItems[key]?.firstIndex(where: { $0.id == boxItemId }) {
                let item = boxItems[key]![idx]
                packedTriplets.remove(tripletKey(item.projectName, item.cabinetName, item.partNumber))
                boxItems[key]?.remove(at: idx)
                break
            }
        }
    }

    // MARK: - Finish

    func finishConsignment(consignmentId: String) async throws -> FinishConsignmentResponse {
        try await simulateDelay()

        let expectedItems = MockData.registryItems(for: consignmentId)
        let packed = boxes[consignmentId]?
            .flatMap { boxItems[$0.id] ?? [] }
            .map { tripletKey($0.projectName, $0.cabinetName, $0.partNumber) } ?? []
        let packedSet = Set(packed)

        let missing = expectedItems.filter { item in
            !packedSet.contains(tripletKey(item.projectName, item.cabinetName, item.partNumber))
        }

        if missing.isEmpty {
            return FinishConsignmentResponse(ok: true, missingItems: nil, message: "Consignment complete!")
        } else {
            return FinishConsignmentResponse(ok: false, missingItems: missing, message: "Missing items found")
        }
    }

    // MARK: - Offline-capable scanning support (mock stubs)

    func fetchPanelRegistry(manifestId: String, projectName: String, etag: String?) async throws -> PanelRegistryResponse {
        try await simulateDelay()
        let entries = MockData.registryItems(for: "cons-001").map { item in
            PanelRegistryEntry(
                panelUid: "\(item.projectName)|\(item.cabinetName)|\(item.partNumber)",
                cabinetName: item.cabinetName,
                partNumber: item.partNumber,
                lengthMm: 600, widthMm: 400, thicknessMm: 18, material: "MDF"
            )
        }
        return PanelRegistryResponse(
            ok: true,
            etag: DateFormatters.iso8601.string(from: Date(timeIntervalSince1970: 0)),
            notModified: nil,
            panels: entries
        )
    }

    func fetchPackedPanels(consignmentId: String) async throws -> PackedPanelsResponse {
        try await simulateDelay()
        let entries = (boxes[consignmentId] ?? []).flatMap { box -> [PackedPanelEntry] in
            (boxItems[box.id] ?? []).map {
                PackedPanelEntry(
                    panelUid: tripletKey($0.projectName, $0.cabinetName, $0.partNumber),
                    boxId: box.id,
                    scannedAt: DateFormatters.iso8601.string(from: $0.scannedAt)
                )
            }
        }
        return PackedPanelsResponse(
            ok: true,
            etag: DateFormatters.iso8601.string(from: Date()),
            panels: entries
        )
    }

    func submitScanBatch(boxId: String, request: ScanBatchRequest) async throws -> ScanBatchResponse {
        try await simulateDelay()
        var results: [ScanBatchItemResult] = []
        for item in request.scans {
            let scanReq = ScanRequest(
                manifestId: request.manifestId,
                consignmentId: request.consignmentId,
                projectName: item.projectName,
                cabinetName: item.cabinetName,
                partNumber: item.partNumber,
                deviceId: item.deviceId,
                stationId: item.stationId,
                operator_: item.operator_,
                scannedAt: item.scannedAt
            )
            let r = try await scanItem(boxId: boxId, request: scanReq)
            results.append(ScanBatchItemResult(
                localId: item.localId,
                ok: r.ok,
                code: r.code ?? (r.ok ? "OK" : "UNKNOWN"),
                boxItemId: r.added?.boxItemId,
                alreadyPackedInBoxId: r.details?.alreadyPackedInBoxId
            ))
        }
        let totalPacked = boxes[request.consignmentId]?
            .reduce(0) { $0 + (boxItems[$1.id]?.count ?? 0) } ?? 0
        return ScanBatchResponse(
            ok: true,
            code: nil,
            reason: nil,
            message: nil,
            results: results,
            boxProgress: ScanBatchResponse.BoxProgress(packedCount: totalPacked, expectedCount: 24)
        )
    }

    // MARK: - Helpers

    private func simulateDelay() async throws {
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
    }

    private func tripletKey(_ project: String, _ cabinet: String, _ part: String) -> String {
        "\(project)|\(cabinet)|\(part)"
    }

    private func findBox(_ boxId: String) -> Box? {
        for list in boxes.values {
            if let box = list.first(where: { $0.id == boxId }) {
                return box
            }
        }
        return nil
    }

    private func replaceBox(_ box: Box) {
        for key in boxes.keys {
            if let idx = boxes[key]?.firstIndex(where: { $0.id == box.id }) {
                boxes[key]?[idx] = box
                return
            }
        }
    }
}
