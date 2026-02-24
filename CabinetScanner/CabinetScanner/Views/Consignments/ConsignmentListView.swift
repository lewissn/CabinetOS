import SwiftUI

struct ConsignmentListView: View {
    @ObservedObject var viewModel: ConsignmentListViewModel

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.consignments.isEmpty {
                ProgressView("Loading consignments...")
            } else if let error = viewModel.errorMessage, viewModel.consignments.isEmpty {
                ContentUnavailableView {
                    Label("Failed to Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.loadConsignments() }
                    }
                }
            } else if viewModel.consignments.isEmpty {
                ContentUnavailableView(
                    "No Consignments",
                    systemImage: "tray",
                    description: Text("No consignments in this manifest")
                )
            } else {
                List(viewModel.consignments) { consignment in
                    NavigationLink(value: consignment) {
                        ConsignmentRow(consignment: consignment)
                    }
                }
                .refreshable {
                    await viewModel.loadConsignments()
                }
            }
        }
        .navigationTitle(viewModel.manifestName)
        .navigationDestination(for: Consignment.self) { consignment in
            BoxListView(
                viewModel: BoxListViewModel(
                    consignment: consignment,
                    manifestId: viewModel.manifestId
                )
            )
        }
        .task {
            await viewModel.loadConsignments()
        }
    }
}

struct ConsignmentRow: View {
    let consignment: Consignment

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(consignment.displayTitle)
                    .font(.headline)

                HStack(spacing: 4) {
                    Text("\(consignment.packedItemCount)")
                        .fontWeight(.semibold)
                    Text("/")
                        .foregroundStyle(.secondary)
                    Text("\(consignment.expectedItemCount)")
                        .foregroundStyle(.secondary)
                    Text("packed")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            Spacer()

            StatusBadge(status: consignment.status)
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let status: Consignment.ConsignmentStatus

    var body: some View {
        Text(status == .complete ? "Complete" : "Open")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(status == .complete ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
            .foregroundStyle(status == .complete ? .green : .blue)
            .clipShape(Capsule())
    }
}
