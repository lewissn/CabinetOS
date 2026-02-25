import SwiftUI
import Foundation

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

final class StockService {

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
        try validate(response)
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
        try validate(response)
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

        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
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

        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private func applyAuth(_ request: inout URLRequest) {
        request.setValue(Configuration.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Configuration.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw StockError.httpError(code)
        }
    }
}

enum StockError: LocalizedError {
    case badURL
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .badURL:              return "Invalid Supabase URL configuration."
        case .httpError(let code): return "Server returned HTTP \(code)."
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

// ============================================================
// MARK: - Stock View (main)
// ============================================================

struct StockView: View {
    @StateObject private var vm = StockViewModel()
    @State private var segment: Segment = .materials

    enum Segment: String, CaseIterable {
        case materials     = "Materials"
        case purchaseList  = "Purchase List"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $segment) {
                    ForEach(Segment.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                switch segment {
                case .materials:
                    MaterialsSectionView(vm: vm)
                case .purchaseList:
                    PurchaseListSectionView(vm: vm)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Stock")
        }
    }
}

// ============================================================
// MARK: - Materials Section
// ============================================================

private struct MaterialsSectionView: View {
    @ObservedObject var vm: StockViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search panels\u{2026}", text: $vm.searchText)
                    .textFieldStyle(.plain)
                if !vm.searchText.isEmpty {
                    Button { vm.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            if vm.materialsLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = vm.materialsError {
                errorView(error) { Task { await vm.loadMaterials() } }
            } else {
                materialsList
            }
        }
        .task { await vm.loadMaterials() }
        .sheet(item: $vm.selectedMaterial) { material in
            MaterialAdjustmentSheet(material: material) { qty in
                Task { await vm.saveAdjustment(materialName: material.materialName, qty: qty) }
            }
        }
    }

    private var materialsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if vm.searchText.isEmpty && !vm.recentlyUpdated.isEmpty {
                    recentSection
                }

                ForEach(vm.filteredMaterials) { material in
                    MaterialRow(material: material)
                        .contentShape(Rectangle())
                        .onTapGesture { vm.selectedMaterial = material }

                    if material.id != vm.filteredMaterials.last?.id {
                        Divider().padding(.leading, 20)
                    }
                }
            }
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently Updated")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            ForEach(vm.recentlyUpdated) { material in
                MaterialRow(material: material)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.selectedMaterial = material }

                if material.id != vm.recentlyUpdated.last?.id {
                    Divider().padding(.leading, 20)
                }
            }
        }
        .padding(.bottom, 12)

        Divider()
            .padding(.vertical, 4)

        Text("All Panels")
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

// ============================================================
// MARK: - Material Row
// ============================================================

private struct MaterialRow: View {
    let material: PanelMaterial

    var body: some View {
        HStack {
            Text(material.materialName)
                .font(.body)
                .lineLimit(2)

            Spacer(minLength: 8)

            if let qty = material.qtySheets {
                Text("\(qty)")
                    .font(.body)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(qty == 0 ? .secondary : .primary)
            } else {
                Text("—")
                    .font(.body)
                    .foregroundStyle(.quaternary)
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// ============================================================
// MARK: - Adjustment Sheet
// ============================================================

private struct MaterialAdjustmentSheet: View {
    let material: PanelMaterial
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantity: Int
    @FocusState private var fieldFocused: Bool

    init(material: PanelMaterial, onSave: @escaping (Int) -> Void) {
        self.material = material
        self.onSave = onSave
        self._quantity = State(initialValue: material.qtySheets ?? 0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Text(material.materialName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                if let current = material.qtySheets {
                    Text("Current stock: \(current) sheets")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No count recorded yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 24) {
                    Button { if quantity > 0 { quantity -= 1 } } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.red)
                    }

                    TextField("0", value: $quantity, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                        .multilineTextAlignment(.center)
                        .font(.title.weight(.bold))
                        .focused($fieldFocused)

                    Button { quantity += 1 } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Adjust Stock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(quantity)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// ============================================================
// MARK: - Purchase List Section
// ============================================================

private struct PurchaseListSectionView: View {
    @ObservedObject var vm: StockViewModel

    var body: some View {
        Group {
            if vm.purchaseLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if let error = vm.purchaseError {
                errorView(error) { Task { await vm.loadPurchaseList() } }
            } else if vm.purchaseItems.isEmpty {
                emptyPurchaseList
            } else {
                purchaseList
            }
        }
        .task { await vm.loadPurchaseList() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    vm.editingPurchaseItem = nil
                    vm.showingPurchaseSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $vm.showingPurchaseSheet) {
            PurchaseItemSheet(editingItem: vm.editingPurchaseItem) { name, qty, note in
                Task {
                    if let existing = vm.editingPurchaseItem {
                        await vm.updatePurchaseItem(id: existing.id, name: name, quantity: qty, note: note)
                    } else {
                        await vm.addPurchaseItem(name: name, quantity: qty, note: note)
                    }
                }
            }
        }
    }

    private var emptyPurchaseList: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "cart")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No items on the purchase list.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Add Item") {
                vm.editingPurchaseItem = nil
                vm.showingPurchaseSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var purchaseList: some View {
        List {
            ForEach(vm.purchaseItems) { item in
                PurchaseItemRowView(item: item)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.editingPurchaseItem = item
                        vm.showingPurchaseSheet = true
                    }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let item = vm.purchaseItems[index]
                    Task { await vm.deletePurchaseItem(id: item.id) }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// ============================================================
// MARK: - Purchase Item Row
// ============================================================

private struct PurchaseItemRowView: View {
    let item: PurchaseItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.itemName)
                    .font(.body)
                    .fontWeight(.medium)

                if let note = item.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Text("×\(item.quantity)")
                .font(.body)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

// ============================================================
// MARK: - Purchase Item Sheet
// ============================================================

private struct PurchaseItemSheet: View {
    let editingItem: PurchaseItem?
    let onSave: (String, Int, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var itemName: String
    @State private var quantity: Int
    @State private var note: String

    init(editingItem: PurchaseItem?, onSave: @escaping (String, Int, String?) -> Void) {
        self.editingItem = editingItem
        self.onSave = onSave
        self._itemName = State(initialValue: editingItem?.itemName ?? "")
        self._quantity = State(initialValue: editingItem?.quantity ?? 1)
        self._note = State(initialValue: editingItem?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Item Name", text: $itemName)
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
                }
                Section("Note") {
                    TextField("Optional note", text: $note)
                }
            }
            .navigationTitle(editingItem == nil ? "Add Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(itemName, quantity, note.isEmpty ? nil : note)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(itemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// ============================================================
// MARK: - Shared error view
// ============================================================

fileprivate func errorView(_ message: String, retry: @escaping () -> Void) -> some View {
    VStack(spacing: 12) {
        Spacer()
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 32))
            .foregroundStyle(.orange)
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        Button("Retry", action: retry)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        Spacer()
    }
    .frame(maxWidth: .infinity)
    .padding(24)
}
