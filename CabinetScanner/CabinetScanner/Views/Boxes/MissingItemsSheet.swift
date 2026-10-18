import CabinetDesign
import SwiftUI

/// What finishing a consignment found still unpacked, grouped by cabinet.
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
        VStack(spacing: 0) {
            PaperTopBar(.close, title: "Not everything's packed", onLeading: onDismiss)
                .screen()
                .padding(.top, PaperSpace.s)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Format.count(missingItems.count, "panel")) \(missingItems.count == 1 ? "isn't" : "aren't") in a box yet, so the consignment stays open.")
                        .paperType(.bodyL, numeric: true)
                        .foregroundStyle(PaperColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, PaperSpace.l)

                    ForEach(groupedItems, id: \.cabinet) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            PaperSectionHeader(group.cabinet) {
                                Text("\(group.items.count)").paperType(.footnote, numeric: true).foregroundStyle(PaperColor.tertiary)
                            }
                            ForEach(group.items, id: \.stableId) { item in
                                RowContainer {
                                    HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                                        Circle().fill(Tone.held.color).frame(width: 7, height: 7)
                                        Code("Part \(item.partNumber)", color: PaperColor.ink, size: 14)
                                        Spacer(minLength: PaperSpace.m)
                                        Text(item.projectName).paperType(.footnote).foregroundStyle(PaperColor.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .section(top: PaperSpace.xxl)
                    }
                }
                .screen()
                .padding(.bottom, PaperSpace.l)
            }
            Button("Keep packing", action: onDismiss)
                .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
                .screen()
                .padding(.vertical, PaperSpace.l)
        }
        .paperBackground()
    }
}
