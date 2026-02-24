import SwiftUI

struct MissingItemsSheet: View {
    let missingItems: [FinishConsignmentResponse.MissingItem]
    let onDismiss: () -> Void

    // Group by cabinet
    private var groupedItems: [(cabinet: String, items: [FinishConsignmentResponse.MissingItem])] {
        let grouped = Dictionary(grouping: missingItems) { $0.cabinetName }
        return grouped
            .sorted { $0.key < $1.key }
            .map { (cabinet: $0.key, items: $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(missingItems.count) items have not been packed")
                            .font(.headline)
                    }
                }

                ForEach(groupedItems, id: \.cabinet) { group in
                    Section(group.cabinet) {
                        ForEach(group.items, id: \.stableId) { item in
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.red)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Part \(item.partNumber)")
                                        .font(.body.weight(.bold))
                                    Text(item.projectName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Missing Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Go Back") {
                        onDismiss()
                    }
                }
            }
        }
    }
}
