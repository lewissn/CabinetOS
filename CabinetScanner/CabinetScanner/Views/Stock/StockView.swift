import CabinetDesign
import SwiftUI

// ============================================================
// MARK: - Stock
// ============================================================
//
// Sheet counts by board, and the purchase list. The data has no reorder
// level, so no board is flagged "order soon"; and purchase items have no
// bought/not-bought state, so they're rows to edit or swipe away rather
// than boxes to tick.

struct StockView: View {
    @StateObject private var vm = StockViewModel()
    @EnvironmentObject private var toaster: Toaster
    @AppStorage("stock.segment") private var segment: Segment = .materials

    enum Segment: String, CaseIterable {
        case materials
        case purchaseList
    }

    private var counted: [PanelMaterial] { vm.materials.filter { $0.qtySheets != nil } }

    var body: some View {
        NavigationStack {
            List {
                ScreenTitle("Stock").paperListRow()

                summary.paperListRow(top: PaperSpace.xxl)

                PaperSegmented([(Segment.materials, "Boards"), (.purchaseList, "To buy")],
                               selection: $segment, accessibilityLabel: "Stock section")
                    .paperListRow(top: PaperSpace.xxl)

                switch segment {
                case .materials: materialsRows
                case .purchaseList: purchaseRows
                }

                Color.clear.frame(height: 120).paperListRow()
            }
            .paperList()
            .refreshable {
                await vm.loadMaterials()
                await vm.loadPurchaseList()
            }
            .paperRootScreen()
            .task {
                await vm.loadMaterials()
                await vm.loadPurchaseList()
            }
            // As before, each section reloads when it's opened, and the screen
            // reloads when you come back to the tab.
            .onChange(of: segment) { _, now in
                Task {
                    if now == .materials { await vm.loadMaterials() } else { await vm.loadPurchaseList() }
                }
            }
            .onTabReturn {
                await vm.loadMaterials()
                await vm.loadPurchaseList()
            }
            .sheet(item: $vm.selectedMaterial) { material in
                CountSheet(material: material) { qty in
                    Task {
                        await vm.saveAdjustment(materialName: material.materialName, qty: qty)
                        if vm.materialsError == nil {
                            toaster.show("\(material.materialName) · \(Format.count(qty, "sheet")) saved")
                        }
                    }
                }
                .paperSheet(detents: [.medium, .large])
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
                .paperSheet(detents: [.medium, .large])
            }
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summary: some View {
        if vm.materials.isEmpty {
            Headline(value: "–", unit: "sheets counted", detail: vm.materialsLoading ? "Loading" : nil)
        } else {
            let total = counted.compactMap(\.qtySheets).reduce(0, +)
            let notCounted = vm.materials.count - counted.count
            Headline(value: PaperFormat.int(total), unit: total == 1 ? "sheet counted" : "sheets counted",
                     detail: "\(Format.count(vm.materials.count, "board")) · \(PaperFormat.int(notCounted)) not counted yet")
        }
    }

    // MARK: Boards

    @ViewBuilder
    private var materialsRows: some View {
        PaperSearchField(text: $vm.searchText, prompt: "Search boards")
            .paperListRow(top: PaperSpace.l)

        if vm.materialsLoading && vm.materials.isEmpty {
            LoadingLine("Loading boards").paperListRow()
        } else if let error = vm.materialsError {
            PaperEmptyState("Stock didn't load", message: error, actionTitle: "Try again") {
                Task { await vm.loadMaterials() }
            }
            .paperListRow()
        } else {
            if vm.searchText.isEmpty && !vm.recentlyUpdated.isEmpty {
                PaperSectionHeader("Recently counted").paperListRow(top: PaperSpace.xxl)
                ForEach(vm.recentlyUpdated) { material in
                    materialButton(material)
                }
            }

            PaperSectionHeader(vm.searchText.isEmpty ? "All boards" : Format.count(vm.filteredMaterials.count, "board")) {
                Text("Tap to count").paperType(.footnote).foregroundStyle(PaperColor.tertiary)
            }
            .paperListRow(top: PaperSpace.section)

            if vm.filteredMaterials.isEmpty {
                Text("No boards match \u{201C}\(vm.searchText)\u{201D}.")
                    .paperType(.subhead).foregroundStyle(PaperColor.secondary)
                    .padding(.vertical, PaperSpace.m)
                    .paperListRow()
            }
            ForEach(vm.filteredMaterials) { material in
                materialButton(material)
            }
        }
    }

    private func materialButton(_ material: PanelMaterial) -> some View {
        Button { vm.selectedMaterial = material } label: {
            MaterialRow(material: material)
        }
        .buttonStyle(.plain)
        .paperListRow()
    }

    // MARK: To buy

    @ViewBuilder
    private var purchaseRows: some View {
        PaperSectionHeader("To buy") {
            Button("Add") {
                vm.editingPurchaseItem = nil
                vm.showingPurchaseSheet = true
            }
            .buttonStyle(.paperText(PaperColor.ink, .footnote, weight: .semibold))
            .accessibilityLabel("Add an item to buy")
        }
        .paperListRow(top: PaperSpace.xxl)

        if vm.purchaseLoading && vm.purchaseItems.isEmpty {
            LoadingLine("Loading the list").paperListRow()
        } else if let error = vm.purchaseError {
            PaperEmptyState("The list didn't load", message: error, actionTitle: "Try again") {
                Task { await vm.loadPurchaseList() }
            }
            .paperListRow()
        } else if vm.purchaseItems.isEmpty {
            PaperEmptyState("Nothing to buy", message: "Add anything the workshop is running low on.", actionTitle: "Add an item") {
                vm.editingPurchaseItem = nil
                vm.showingPurchaseSheet = true
            }
            .paperListRow()
        } else {
            ForEach(vm.purchaseItems) { item in
                Button {
                    vm.editingPurchaseItem = item
                    vm.showingPurchaseSheet = true
                } label: {
                    PurchaseItemRowView(item: item)
                }
                .buttonStyle(.plain)
                .paperListRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await vm.deletePurchaseItem(id: item.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Text("Tap an item to change it. Swipe left to take it off the list.")
                .paperType(.footnote)
                .foregroundStyle(PaperColor.tertiary)
                .padding(.top, PaperSpace.m)
                .paperListRow()
        }
    }
}

// ============================================================
// MARK: - Rows
// ============================================================

private struct MaterialRow: View {
    let material: PanelMaterial

    var body: some View {
        RowContainer(minHeight: 60) {
            HStack(alignment: .center, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(material.materialName).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(2)
                    Text(material.qtySheets == nil
                         ? "Not counted yet"
                         : material.updatedAt.map { "Counted \(Format.when($0))" } ?? "Counted")
                        .paperType(.footnote, numeric: true)
                        .foregroundStyle(PaperColor.secondary)
                }
                Spacer(minLength: PaperSpace.m)
                Text(material.qtySheets.map { PaperFormat.int($0) } ?? "–")
                    .paperType(.figureS, numeric: true)
                    .foregroundStyle(material.qtySheets == nil ? PaperColor.faint : PaperColor.ink)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the count")
    }
}

private struct PurchaseItemRowView: View {
    let item: PurchaseItem

    var body: some View {
        RowContainer {
            HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.itemName).paperType(.body).foregroundStyle(PaperColor.ink)
                    if let note = item.note, !note.isEmpty {
                        Text(note).paperType(.footnote).foregroundStyle(PaperColor.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: PaperSpace.m)
                Text("× \(PaperFormat.int(item.quantity))")
                    .paperType(.subhead, numeric: true)
                    .foregroundStyle(PaperColor.body)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// ============================================================
// MARK: - Count sheet
// ============================================================

/// A big number between two 60 pt buttons; the number can be typed too.
private struct CountSheet: View {
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
        VStack(alignment: .leading, spacing: 0) {
            SheetScreen("Count", scrolls: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(material.materialName)
                        .paperType(.headline)
                        .foregroundStyle(PaperColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, PaperSpace.l)
                    Text(material.qtySheets.map { "Last count \(Format.count($0, "sheet"))" + (material.updatedAt.map { ", \(Format.when($0))" } ?? "") }
                         ?? "Not counted before")
                        .paperType(.footnote, numeric: true)
                        .foregroundStyle(PaperColor.secondary)
                        .padding(.top, PaperSpace.xxs)

                    HStack(spacing: PaperSpace.xl) {
                        stepper(.minus, label: "One fewer") { quantity = max(0, quantity - 1) }
                        TextField("0", value: $quantity, format: .number)
                            .paperType(.heroXL, numeric: true)
                            .foregroundStyle(PaperColor.ink)
                            .multilineTextAlignment(.center)
                            .keyboardType(.numberPad)
                            .focused($fieldFocused)
                            .frame(minWidth: 120)
                            .accessibilityLabel("Sheets")
                        stepper(.plus, label: "One more") { quantity += 1 }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, PaperSpace.xxl)
                    Text("sheets").paperType(.subhead).foregroundStyle(PaperColor.secondary).frame(maxWidth: .infinity)
                    Spacer(minLength: PaperSpace.l)
                }
            }
            Button("Save count") {
                onSave(quantity)
                dismiss()
            }
            .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
            .screen()
            .padding(.vertical, PaperSpace.l)
        }
        .paperBackground()
    }

    private func stepper(_ glyph: PaperGlyph, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            PaperIcon(glyph, size: 22, lineWidth: 2)
                .frame(width: 60, height: 60)
                .overlay(Circle().strokeBorder(PaperColor.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
        SheetScreen(editingItem == nil ? "Add an item" : "Change item") {
            VStack(alignment: .leading, spacing: PaperSpace.xxl) {
                PaperUnderlineField("Item", text: $itemName, placeholder: "What to buy")
                    .padding(.top, PaperSpace.l)

                VStack(alignment: .leading, spacing: PaperSpace.s) {
                    PaperLabel("Quantity")
                    HStack(spacing: PaperSpace.l) {
                        quantityButton(.minus, label: "One fewer") { quantity = max(1, quantity - 1) }
                        Text(PaperFormat.int(quantity))
                            .paperType(.figure, numeric: true)
                            .foregroundStyle(PaperColor.ink)
                            .frame(minWidth: 48)
                            .contentTransition(.numericText())
                        quantityButton(.plus, label: "One more") { quantity = min(9999, quantity + 1) }
                    }
                }

                PaperUnderlineField("Note (optional)", text: $note)

                Button("Save") {
                    onSave(itemName, quantity, note.isEmpty ? nil : note)
                    dismiss()
                }
                .buttonStyle(.paperPill(.accent, .large, fullWidth: true))
                .disabled(itemName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func quantityButton(_ glyph: PaperGlyph, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy) { action() }
        } label: {
            PaperIcon(glyph, size: 18, lineWidth: 2)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(PaperColor.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
