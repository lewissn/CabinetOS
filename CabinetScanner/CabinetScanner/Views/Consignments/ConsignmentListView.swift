import CabinetDesign
import SwiftUI

/// A manifest's consignments, each with what's packed of what's expected.
struct ConsignmentListView: View {
    @ObservedObject var viewModel: ConsignmentListViewModel

    private var packed: Int { viewModel.consignments.reduce(0) { $0 + $1.packedItemCount } }
    private var expected: Int { viewModel.consignments.reduce(0) { $0 + $1.expectedItemCount } }
    private var complete: Int { viewModel.consignments.filter { $0.status == .complete }.count }

    var body: some View {
        PushedScreen(back: "Packing", onRefresh: { await viewModel.loadConsignments() }) {
            VStack(alignment: .leading, spacing: 0) {
                Text(viewModel.manifestName)
                    .paperType(.largeTitle)
                    .foregroundStyle(PaperColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if viewModel.isLoading && viewModel.consignments.isEmpty {
                    LoadingLine("Loading consignments").section(top: PaperSpace.xxl)
                } else if let error = viewModel.errorMessage, viewModel.consignments.isEmpty {
                    PaperEmptyState("Consignments didn't load", message: error, actionTitle: "Try again") {
                        Task { await viewModel.loadConsignments() }
                    }
                    .section(top: PaperSpace.xxl)
                } else if viewModel.consignments.isEmpty {
                    PaperEmptyState("No consignments", message: "This manifest has no consignments.")
                        .section(top: PaperSpace.xxl)
                } else {
                    summary.section(top: PaperSpace.xxl)
                    VStack(alignment: .leading, spacing: 0) {
                        PaperSectionHeader("Consignments")
                        ForEach(viewModel.consignments) { consignment in
                            NavigationLink(value: consignment) {
                                ConsignmentRow(consignment: consignment)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .section()
                }
            }
            .screen()
        }
        .navigationDestination(for: Consignment.self) { consignment in
            BoxListView(
                consignment: consignment,
                manifestId: viewModel.manifestId,
                manifestName: viewModel.manifestName
            )
        }
        .task {
            await viewModel.loadConsignments()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: PaperSpace.l) {
            Headline(value: PaperFormat.int(packed), unit: "of \(PaperFormat.int(expected)) panels packed",
                     detail: "\(Format.count(viewModel.consignments.count, "consignment")) · \(complete) complete")
            if expected > 0 {
                PaperBar(Double(packed) / Double(expected),
                         color: packed >= expected ? PaperColor.ink : PaperColor.accent, height: 4)
            }
        }
    }
}

struct ConsignmentRow: View {
    let consignment: Consignment

    var body: some View {
        RowContainer {
            HStack(alignment: .center, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(consignment.title).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(1)
                    if let ref = consignment.jobRef {
                        Code(ref)
                    }
                }
                Spacer(minLength: PaperSpace.m)
                VStack(alignment: .trailing, spacing: 3) {
                    StatusText(consignment.statusLabel, tone: consignment.tone)
                    Text(consignment.packedLine).paperType(.caption, numeric: true).foregroundStyle(PaperColor.tertiary)
                }
                PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
