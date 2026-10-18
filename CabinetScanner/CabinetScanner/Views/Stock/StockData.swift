import Foundation

// Stock's data: panel counts and the purchase list, read and written straight
// to Supabase. Moved out of StockView.swift unchanged in the design refresh;
// the calls are as they were.

// ============================================================
// MARK: - Models
// ============================================================

struct PanelMaterial: Identifiable {
    var id: String { materialName }
    let materialName: String
    var qtySheets: Int?
    var updatedAt: Date?
}

struct PurchaseItem: Identifiable {
    let id: String
    var itemName: String
    var quantity: Int
    var note: String?
    var createdAt: Date?
}

// ============================================================
// MARK: - Decodable rows
// ============================================================

private struct PanelNameRow: Decodable {
    let materialName: String

    enum CodingKeys: String, CodingKey {
        case materialName = "material_name"
    }
}

private struct PanelStockRow: Decodable {
    let materialName: String
    let qtySheets: Int?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case materialName = "material_name"
        case qtySheets    = "qty_sheets"
        case updatedAt    = "updated_at"
    }
}

private struct PurchaseItemRow: Decodable {
    let id: String
    let itemName: String
    let quantity: Int
    let note: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case itemName  = "item_name"
        case quantity
        case note
        case createdAt = "created_at"
    }

    func toModel() -> PurchaseItem {
        PurchaseItem(
            id: id,
            itemName: itemName,
            quantity: quantity,
            note: note,
            createdAt: createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }
}

// ============================================================
// MARK: - Encodable bodies
// ============================================================

private struct UpsertStockBody: Encodable {
    let materialName: String
    let qtySheets: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case materialName = "material_name"
        case qtySheets    = "qty_sheets"
        case updatedAt    = "updated_at"
    }
}

private struct PurchaseItemBody: Encodable {
    let itemName: String
    let quantity: Int
    let note: String?

    enum CodingKeys: String, CodingKey {
        case itemName = "item_name"
        case quantity
        case note
    }
}

// ============================================================
// MARK: - Service
// ============================================================

private final class StockService {

    func fetchPanelNames() async throws -> [String] {
        let data = try await supabaseGet(
            table: "price_library_panels",
            select: "material_name",
            order: "material_name.asc"
        )
        let rows = try JSONDecoder().decode([PanelNameRow].self, from: data)
        return rows.map(\.materialName)
    }

    func fetchPanelStock() async throws -> [PanelStockRow] {
        let data = try await supabaseGet(
            table: "panel_stock",
            select: "material_name,qty_sheets,updated_at",
            order: "updated_at.desc"
        )
        return try JSONDecoder().decode([PanelStockRow].self, from: data)
    }

    func upsertStock(materialName: String, qty: Int) async throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let body = UpsertStockBody(
            materialName: materialName,
            qtySheets: qty,
            updatedAt: iso.string(from: Date())
        )
        let bodyData = try JSONEncoder().encode(body)
        try await supabasePost(
            table: "panel_stock",
            body: bodyData,
            extraHeaders: ["Prefer": "resolution=merge-duplicates, return=minimal"]
        )
    }

    // MARK: Purchase list

    func fetchPurchaseList() async throws -> [PurchaseItem] {
        let data = try await supabaseGet(
            table: "purchase_list",
            select: "*",
            order: "created_at.desc"
        )
        return try JSONDecoder().decode([PurchaseItemRow].self, from: data).map { $0.toModel() }
    }

    func addPurchaseItem(name: String, quantity: Int, note: String?) async throws {
        let body = PurchaseItemBody(itemName: name, quantity: quantity, note: note)
        let bodyData = try JSONEncoder().encode(body)
        try await supabasePost(
            table: "purchase_list",
            body: bodyData,
            extraHeaders: ["Prefer": "return=minimal"]
        )
    }

    func updatePurchaseItem(id: String, name: String, quantity: Int, note: String?) async throws {
        let body = PurchaseItemBody(itemName: name, quantity: quantity, note: note)
        let bodyData = try JSONEncoder().encode(body)
        try await supabasePatch(
            table: "purchase_list",
            filter: "id=eq.\(id)",
            body: bodyData
        )
    }

    func deletePurchaseItem(id: String) async throws {
        try await supabaseDelete(table: "purchase_list", filter: "id=eq.\(id)")
    }

    // MARK: - Supabase HTTP helpers

    private func supabaseGet(table: String, select: String, order: String? = nil) async throws -> Data {
        var components = URLComponents(string: Configuration.supabaseURL + "/rest/v1/" + table)!
        var items = [URLQueryItem(name: "select", value: select)]
        if let order { items.append(URLQueryItem(name: "order", value: order)) }
        components.queryItems = items

        guard let url = components.url else { throw StockError.badURL }

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
            throw StockError.badURL
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

        guard let url = components.url else { throw StockError.badURL }

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

        guard let url = components.url else { throw StockError.badURL }

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
            throw StockError.httpError(code, detail: body)
        }
    }
}

enum StockError: LocalizedError {
    case badURL
    case httpError(Int, detail: String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid Supabase URL configuration."
        case .httpError(let code, let detail):
            if detail.isEmpty { return "Server returned HTTP \(code)." }
            return "HTTP \(code): \(detail)"
        }
    }
}

// ============================================================
// MARK: - ViewModel
// ============================================================

@MainActor
final class StockViewModel: ObservableObject {

    // Materials
    @Published var materials: [PanelMaterial] = []
    @Published var recentlyUpdated: [PanelMaterial] = []
    @Published var searchText = ""
    @Published var materialsLoading = false
    @Published var materialsError: String?

    // Adjustment sheet
    @Published var selectedMaterial: PanelMaterial?

    // Purchase list
    @Published var purchaseItems: [PurchaseItem] = []
    @Published var purchaseLoading = false
    @Published var purchaseError: String?

    // Purchase sheet
    @Published var showingPurchaseSheet = false
    @Published var editingPurchaseItem: PurchaseItem?

    private let service = StockService()

    var filteredMaterials: [PanelMaterial] {
        if searchText.isEmpty { return materials }
        return materials.filter {
            $0.materialName.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: Materials

    func loadMaterials() async {
        materialsLoading = true
        materialsError = nil
        do {
            async let namesTask = service.fetchPanelNames()
            async let stockTask = service.fetchPanelStock()

            let names = try await namesTask
            let stockRows = try await stockTask

            let stockMap = Dictionary(
                stockRows.map { ($0.materialName, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            materials = names.map { name in
                let stock = stockMap[name]
                return PanelMaterial(
                    materialName: name,
                    qtySheets: stock?.qtySheets,
                    updatedAt: stock?.updatedAt.flatMap { iso.date(from: $0) }
                )
            }

            recentlyUpdated = stockRows.prefix(10).compactMap { row in
                materials.first { $0.materialName == row.materialName }
            }

            materialsLoading = false
        } catch {
            materialsError = error.localizedDescription
            materialsLoading = false
        }
    }

    func saveAdjustment(materialName: String, qty: Int) async {
        do {
            try await service.upsertStock(materialName: materialName, qty: qty)
            await loadMaterials()
        } catch {
            materialsError = error.localizedDescription
        }
    }

    // MARK: Purchase list

    func loadPurchaseList() async {
        purchaseLoading = true
        purchaseError = nil
        do {
            purchaseItems = try await service.fetchPurchaseList()
            purchaseLoading = false
        } catch {
            purchaseError = error.localizedDescription
            purchaseLoading = false
        }
    }

    func addPurchaseItem(name: String, quantity: Int, note: String?) async {
        do {
            try await service.addPurchaseItem(name: name, quantity: quantity, note: note)
            await loadPurchaseList()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func updatePurchaseItem(id: String, name: String, quantity: Int, note: String?) async {
        do {
            try await service.updatePurchaseItem(id: id, name: name, quantity: quantity, note: note)
            await loadPurchaseList()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func deletePurchaseItem(id: String) async {
        do {
            try await service.deletePurchaseItem(id: id)
            await loadPurchaseList()
        } catch {
            purchaseError = error.localizedDescription
        }
    }
}
