import Foundation

// MARK: - Supabase CRUD for manual_manifests, manual_manifest_boxes, manual_manifest_items

final class ManualManifestService {

    // MARK: - Manifests

    func fetchManifests() async throws -> [ManualManifest] {
        let data = try await supabaseGet(
            table: "manual_manifests",
            select: "*",
            order: "created_at.desc"
        )
        let rows = try JSONDecoder().decode([MMManifestRow].self, from: data)
        return rows.map { $0.toModel() }
    }

    func createManifest(name: String, courier: String?, note: String?) async throws -> ManualManifest {
        let body = CreateManifestBody(
            manifest_name: name,
            courier: courier,
            note: note,
            status: "open"
        )
        let bodyData = try JSONEncoder().encode(body)
        let data = try await supabasePost(
            table: "manual_manifests",
            body: bodyData,
            extraHeaders: ["Prefer": "return=representation"]
        )
        let rows = try JSONDecoder().decode([MMManifestRow].self, from: data)
        guard let row = rows.first else { throw ManualManifestError.createFailed }
        return row.toModel()
    }

    func finishManifest(id: String) async throws {
        let body = try JSONEncoder().encode(["status": "finished"])
        try await supabasePatch(
            table: "manual_manifests",
            filter: "id=eq.\(id)",
            body: body
        )
    }

    func reopenManifest(id: String) async throws {
        let body = try JSONEncoder().encode(["status": "open"])
        try await supabasePatch(
            table: "manual_manifests",
            filter: "id=eq.\(id)",
            body: body
        )
    }

    // MARK: - Boxes

    func fetchBoxes(manifestId: String) async throws -> [ManualManifestBox] {
        let data = try await supabaseGet(
            table: "manual_manifest_boxes",
            select: "*",
            filter: "manifest_id=eq.\(manifestId)",
            order: "box_number.asc"
        )
        let rows = try JSONDecoder().decode([MMBoxRow].self, from: data)
        return rows.map { $0.toModel() }
    }

    func createBox(manifestId: String, boxNumber: Int) async throws -> ManualManifestBox {
        let body = CreateBoxBody(
            manifest_id: manifestId,
            box_number: boxNumber,
            status: "open"
        )
        let bodyData = try JSONEncoder().encode(body)
        let data = try await supabasePost(
            table: "manual_manifest_boxes",
            body: bodyData,
            extraHeaders: ["Prefer": "return=representation"]
        )
        let rows = try JSONDecoder().decode([MMBoxRow].self, from: data)
        guard let row = rows.first else { throw ManualManifestError.createFailed }
        return row.toModel()
    }

    func closeBox(id: String, lengthMM: Int, widthMM: Int, heightMM: Int, weightKG: Double) async throws {
        let body = CloseBoxBody(
            status: "closed",
            length_mm: lengthMM,
            width_mm: widthMM,
            height_mm: heightMM,
            weight_kg: weightKG
        )
        let bodyData = try JSONEncoder().encode(body)
        try await supabasePatch(
            table: "manual_manifest_boxes",
            filter: "id=eq.\(id)",
            body: bodyData
        )
    }

    func closeBoxSimple(id: String) async throws {
        let body = try JSONEncoder().encode(["status": "closed"])
        try await supabasePatch(
            table: "manual_manifest_boxes",
            filter: "id=eq.\(id)",
            body: body
        )
    }

    func updateBoxDimensions(id: String, lengthMM: Int, widthMM: Int, heightMM: Int, weightKG: Double) async throws {
        let body = UpdateDimensionsBody(
            length_mm: lengthMM,
            width_mm: widthMM,
            height_mm: heightMM,
            weight_kg: weightKG
        )
        let bodyData = try JSONEncoder().encode(body)
        try await supabasePatch(
            table: "manual_manifest_boxes",
            filter: "id=eq.\(id)",
            body: bodyData
        )
    }

    func reopenBox(id: String) async throws {
        let body = try JSONEncoder().encode(["status": "open"])
        try await supabasePatch(
            table: "manual_manifest_boxes",
            filter: "id=eq.\(id)",
            body: body
        )
    }

    func deleteBox(id: String) async throws {
        try await supabaseDelete(table: "manual_manifest_items", filter: "box_id=eq.\(id)")
        try await supabaseDelete(table: "manual_manifest_boxes", filter: "id=eq.\(id)")
    }

    // MARK: - Items

    func fetchItems(boxId: String) async throws -> [ManualManifestItem] {
        let data = try await supabaseGet(
            table: "manual_manifest_items",
            select: "*",
            filter: "box_id=eq.\(boxId)",
            order: "created_at.asc"
        )
        let rows = try JSONDecoder().decode([MMItemRow].self, from: data)
        return rows.map { $0.toModel() }
    }

    /// Upsert a scanned label item — merges by (box_id + project + cabinet + part)
    func upsertLabelItem(boxId: String, projectName: String, cabinetName: String, partNumber: String) async throws -> ManualManifestItem {
        let existing = try await fetchItems(boxId: boxId)
        if let match = existing.first(where: {
            $0.itemType == .label &&
            $0.projectName == projectName &&
            $0.cabinetName == cabinetName &&
            $0.partNumber == partNumber
        }) {
            let newQty = match.qty + 1
            let body = try JSONEncoder().encode(["qty": newQty])
            try await supabasePatch(
                table: "manual_manifest_items",
                filter: "id=eq.\(match.id)",
                body: body
            )
            return ManualManifestItem(
                id: match.id, boxId: boxId, itemType: .label,
                projectName: projectName, cabinetName: cabinetName,
                partNumber: partNumber, manualItemName: nil,
                qty: newQty, createdAt: match.createdAt
            )
        } else {
            let body = CreateLabelItemBody(
                box_id: boxId,
                item_type: "label",
                project_name: projectName,
                cabinet_name: cabinetName,
                part_number: partNumber,
                qty: 1
            )
            let bodyData = try JSONEncoder().encode(body)
            let data = try await supabasePost(
                table: "manual_manifest_items",
                body: bodyData,
                extraHeaders: ["Prefer": "return=representation"]
            )
            let rows = try JSONDecoder().decode([MMItemRow].self, from: data)
            guard let row = rows.first else { throw ManualManifestError.createFailed }
            return row.toModel()
        }
    }

    /// Upsert a manual item — merges by (box_id + manual_item_name)
    func upsertManualItem(boxId: String, itemName: String, quantity: Int) async throws -> ManualManifestItem {
        let existing = try await fetchItems(boxId: boxId)
        if let match = existing.first(where: {
            $0.itemType == .manual && $0.manualItemName == itemName
        }) {
            let newQty = match.qty + quantity
            let body = try JSONEncoder().encode(["qty": newQty])
            try await supabasePatch(
                table: "manual_manifest_items",
                filter: "id=eq.\(match.id)",
                body: body
            )
            return ManualManifestItem(
                id: match.id, boxId: boxId, itemType: .manual,
                projectName: nil, cabinetName: nil, partNumber: nil,
                manualItemName: itemName, qty: newQty, createdAt: match.createdAt
            )
        } else {
            let body = CreateManualItemBody(
                box_id: boxId,
                item_type: "manual",
                manual_item_name: itemName,
                qty: quantity
            )
            let bodyData = try JSONEncoder().encode(body)
            let data = try await supabasePost(
                table: "manual_manifest_items",
                body: bodyData,
                extraHeaders: ["Prefer": "return=representation"]
            )
            let rows = try JSONDecoder().decode([MMItemRow].self, from: data)
            guard let row = rows.first else { throw ManualManifestError.createFailed }
            return row.toModel()
        }
    }

    func deleteItem(id: String) async throws {
        try await supabaseDelete(table: "manual_manifest_items", filter: "id=eq.\(id)")
    }

    // MARK: - Supabase HTTP helpers (same pattern as StockView)

    private func supabaseGet(table: String, select: String, filter: String? = nil, order: String? = nil) async throws -> Data {
        var components = URLComponents(string: Configuration.supabaseURL + "/rest/v1/" + table)!
        var items = [URLQueryItem(name: "select", value: select)]
        if let filter {
            let parts = filter.split(separator: "&")
            for part in parts {
                let kv = part.split(separator: "=", maxSplits: 1)
                if kv.count == 2 {
                    items.append(URLQueryItem(name: String(kv[0]), value: String(kv[1])))
                }
            }
        }
        if let order { items.append(URLQueryItem(name: "order", value: order)) }
        components.queryItems = items

        guard let url = components.url else { throw ManualManifestError.badURL }
        var request = URLRequest(url: url)
        applyAuth(&request)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return data
    }

    @discardableResult
    private func supabasePost(table: String, body: Data, extraHeaders: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: Configuration.supabaseURL + "/rest/v1/" + table) else {
            throw ManualManifestError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyAuth(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        return data
    }

    private func supabasePatch(table: String, filter: String, body: Data) async throws {
        var components = URLComponents(string: Configuration.supabaseURL + "/rest/v1/" + table)!
        components.queryItems = filter.split(separator: "&").map { part in
            let kv = part.split(separator: "=", maxSplits: 1)
            return URLQueryItem(name: String(kv[0]), value: kv.count > 1 ? String(kv[1]) : nil)
        }
        guard let url = components.url else { throw ManualManifestError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        applyAuth(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
    }

    private func supabaseDelete(table: String, filter: String) async throws {
        var components = URLComponents(string: Configuration.supabaseURL + "/rest/v1/" + table)!
        components.queryItems = filter.split(separator: "&").map { part in
            let kv = part.split(separator: "=", maxSplits: 1)
            return URLQueryItem(name: String(kv[0]), value: kv.count > 1 ? String(kv[1]) : nil)
        }
        guard let url = components.url else { throw ManualManifestError.badURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        applyAuth(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
    }

    private func applyAuth(_ request: inout URLRequest) {
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw ManualManifestError.httpError(code, detail: body)
        }
    }
}

// MARK: - Decodable rows

private struct MMManifestRow: Decodable {
    let id: String
    let manifest_name: String
    let courier: String?
    let status: String
    let note: String?
    let created_at: String
    let updated_at: String

    // Added when consignments could be raised from a job page. Optional so a
    // response from before the migration still decodes.
    let job_index_id: String?
    let job_reference: String?
    let steps_completed_at: String?

    func toModel() -> ManualManifest {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ManualManifest(
            id: id,
            manifestName: manifest_name,
            courier: courier,
            status: ManualManifest.ManualManifestStatus(rawValue: status) ?? .open,
            note: note,
            createdAt: iso.date(from: created_at) ?? Date(),
            updatedAt: iso.date(from: updated_at) ?? Date(),
            jobIndexId: job_index_id,
            jobReference: job_reference,
            stepsCompletedAt: steps_completed_at.flatMap { iso.date(from: $0) }
        )
    }
}

private struct MMBoxRow: Decodable {
    let id: String
    let manifest_id: String
    let box_number: Int
    let status: String
    let length_mm: Int?
    let width_mm: Int?
    let height_mm: Int?
    let weight_kg: Double?
    let created_at: String

    func toModel() -> ManualManifestBox {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ManualManifestBox(
            id: id,
            manifestId: manifest_id,
            boxNumber: box_number,
            status: ManualManifestBox.BoxStatus(rawValue: status) ?? .open,
            lengthMM: length_mm,
            widthMM: width_mm,
            heightMM: height_mm,
            weightKG: weight_kg,
            createdAt: iso.date(from: created_at) ?? Date()
        )
    }
}

private struct MMItemRow: Decodable {
    let id: String
    let box_id: String
    let item_type: String
    let project_name: String?
    let cabinet_name: String?
    let part_number: String?
    let manual_item_name: String?
    let qty: Int
    let created_at: String

    func toModel() -> ManualManifestItem {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return ManualManifestItem(
            id: id,
            boxId: box_id,
            itemType: ManualManifestItem.ItemType(rawValue: item_type) ?? .manual,
            projectName: project_name,
            cabinetName: cabinet_name,
            partNumber: part_number,
            manualItemName: manual_item_name,
            qty: qty,
            createdAt: iso.date(from: created_at) ?? Date()
        )
    }
}

// MARK: - Encodable request bodies

private struct CreateManifestBody: Encodable {
    let manifest_name: String
    let courier: String?
    let note: String?
    let status: String
}

private struct CreateBoxBody: Encodable {
    let manifest_id: String
    let box_number: Int
    let status: String
}

private struct CloseBoxBody: Encodable {
    let status: String
    let length_mm: Int
    let width_mm: Int
    let height_mm: Int
    let weight_kg: Double
}

private struct UpdateDimensionsBody: Encodable {
    let length_mm: Int
    let width_mm: Int
    let height_mm: Int
    let weight_kg: Double
}

private struct CreateLabelItemBody: Encodable {
    let box_id: String
    let item_type: String
    let project_name: String
    let cabinet_name: String
    let part_number: String
    let qty: Int
}

private struct CreateManualItemBody: Encodable {
    let box_id: String
    let item_type: String
    let manual_item_name: String
    let qty: Int
}

// MARK: - Errors

enum ManualManifestError: LocalizedError {
    case badURL
    case createFailed
    case httpError(Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid Supabase URL."
        case .createFailed: return "Failed to create record."
        case .httpError(let code, let detail):
            if detail.isEmpty { return "Server returned HTTP \(code)." }
            return "HTTP \(code): \(detail)"
        }
    }
}
