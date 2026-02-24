import SwiftUI

struct ManifestListView: View {
    @StateObject private var viewModel = ManifestListViewModel()
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.manifests.isEmpty {
                ProgressView("Loading manifests...")
            } else if let error = viewModel.errorMessage, viewModel.manifests.isEmpty {
                ContentUnavailableView {
                    Label("Failed to Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.loadManifests() }
                    }
                }
            } else if viewModel.manifests.isEmpty {
                ContentUnavailableView(
                    "No Manifests",
                    systemImage: "doc.text",
                    description: Text("No active manifests found")
                )
            } else {
                List(viewModel.manifests) { manifest in
                    NavigationLink(value: manifest) {
                        ManifestRow(manifest: manifest)
                    }
                }
                .refreshable {
                    await viewModel.loadManifests()
                }
            }
        }
        .navigationTitle("Manifests")
        .navigationDestination(for: Manifest.self) { manifest in
            ConsignmentListView(
                viewModel: ConsignmentListViewModel(
                    manifestId: manifest.id,
                    manifestName: manifest.name
                )
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Navigate to station settings
                    appState.isStationConfigured = false
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task {
            await viewModel.loadManifests()
        }
    }
}

struct ManifestRow: View {
    let manifest: Manifest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(manifest.name)
                .font(.headline)

            HStack {
                Label("\(manifest.consignmentCount) consignments", systemImage: "tray.full")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(manifest.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
