import CabinetDesign
import SwiftUI

/// The BJS manifests, as rows on the Packing screen. `Manifest` carries a
/// name and a consignment count but no panel totals, so rows don't show a
/// packed bar.
struct BJSManifestList: View {
    @ObservedObject var viewModel: ManifestListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Manifests") {
                if !viewModel.manifests.isEmpty {
                    Text("\(viewModel.manifests.count)").paperType(.footnote, numeric: true)
                        .foregroundStyle(PaperColor.tertiary)
                }
            }

            if viewModel.isLoading && viewModel.manifests.isEmpty {
                LoadingLine("Loading manifests")
            } else if let error = viewModel.errorMessage, viewModel.manifests.isEmpty {
                PaperEmptyState("Manifests didn't load", message: error, actionTitle: "Try again") {
                    Task { await viewModel.loadManifests() }
                }
            } else if viewModel.manifests.isEmpty {
                PaperEmptyState("No BJS manifests", message: "Active manifests appear here once they're uploaded.")
            } else {
                ForEach(viewModel.manifests) { manifest in
                    NavigationLink(value: manifest) {
                        ManifestRow(manifest: manifest)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ManifestRow: View {
    let manifest: Manifest

    var body: some View {
        RowContainer(verticalPadding: PaperSpace.l) {
            HStack(alignment: .center, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(manifest.name).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(2)
                    Text("\(Format.count(manifest.consignmentCount, "consignment")) · \(PaperFormat.relativeDay(manifest.createdAt))")
                        .paperType(.footnote, numeric: true)
                        .foregroundStyle(PaperColor.secondary)
                }
                Spacer(minLength: PaperSpace.m)
                if manifest.status == .complete {
                    StatusText("Complete", tone: .done)
                }
                PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
