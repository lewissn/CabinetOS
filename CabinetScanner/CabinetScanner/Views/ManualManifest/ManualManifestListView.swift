import CabinetDesign
import SwiftUI

/// Courier manifests, as rows on the Packing screen. These are read and
/// written straight to Supabase by ManualManifestService, as before.
struct CourierManifestList: View {
    @ObservedObject var viewModel: ManualManifestListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isLoading && viewModel.manifests.isEmpty {
                header("Courier manifests")
                LoadingLine("Loading manifests")
            } else if let error = viewModel.errorMessage, viewModel.manifests.isEmpty {
                header("Courier manifests")
                PaperEmptyState("Manifests didn't load", message: error, actionTitle: "Try again") {
                    Task { await viewModel.loadManifests() }
                }
            } else if viewModel.manifests.isEmpty {
                header("Courier manifests")
                PaperEmptyState("No courier manifests", message: "Start one for an APC or ParcelForce consignment.",
                                actionTitle: "New manifest") { viewModel.showCreateSheet = true }
            } else {
                if !viewModel.openManifests.isEmpty {
                    header("Open")
                    ForEach(viewModel.openManifests) { manifest in
                        NavigationLink(value: manifest) { ManualManifestRow(manifest: manifest) }
                            .buttonStyle(.plain)
                    }
                }
                if !viewModel.finishedManifests.isEmpty {
                    PaperSectionHeader("Finished")
                        .padding(.top, viewModel.openManifests.isEmpty ? 0 : PaperSpace.section)
                    ForEach(viewModel.finishedManifests) { manifest in
                        NavigationLink(value: manifest) { ManualManifestRow(manifest: manifest) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func header(_ title: String) -> some View {
        PaperSectionHeader(title) {
            Button("New") { viewModel.showCreateSheet = true }
                .buttonStyle(.paperText(PaperColor.ink, .footnote, weight: .semibold))
                .accessibilityLabel("New courier manifest")
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ManualManifestListViewModel: ObservableObject {
    @Published var manifests: [ManualManifest] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showCreateSheet = false
    @Published var toastMessage: String?

    private let service = ManualManifestService()

    var openManifests: [ManualManifest] { manifests.filter { !$0.isFinished } }
    var finishedManifests: [ManualManifest] { manifests.filter { $0.isFinished } }

    func loadManifests() async {
        isLoading = true
        errorMessage = nil
        do {
            manifests = try await service.fetchManifests()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createManifest(name: String, courier: String?, note: String?) async {
        do {
            let manifest = try await service.createManifest(name: name, courier: courier, note: note)
            manifests.insert(manifest, at: 0)
            toastMessage = "Manifest created"
            HapticService.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticService.error()
        }
    }
}

// MARK: - Manual Manifest Row

struct ManualManifestRow: View {
    let manifest: ManualManifest

    private var detail: String {
        var parts: [String] = []
        if let courier = manifest.courier, !courier.isEmpty { parts.append(courier) }
        if let ref = manifest.jobReference, !ref.isEmpty { parts.append(ref) }
        parts.append(PaperFormat.relativeDay(manifest.createdAt))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        RowContainer(verticalPadding: PaperSpace.l) {
            HStack(alignment: .center, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(manifest.manifestName).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(2)
                    Text(detail).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary).lineLimit(1)
                }
                Spacer(minLength: PaperSpace.m)
                StatusText(manifest.isFinished ? "Finished" : "Open", tone: manifest.isFinished ? .done : .progress)
                PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Create Manual Manifest Sheet

struct CreateManualManifestSheet: View {
    let onCreate: (String, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var manifestName = ""
    @State private var selectedCourier = ""
    @State private var note = ""

    private let courierOptions = ["APC", "ParcelForce", "Other"]

    private var canCreate: Bool { !manifestName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        SheetScreen("New courier manifest") {
            VStack(alignment: .leading, spacing: PaperSpace.xxl) {
                PaperUnderlineField("Manifest name", text: $manifestName, placeholder: "Customer or job")
                    .textInputAutocapitalization(.words)
                    .padding(.top, PaperSpace.l)

                VStack(alignment: .leading, spacing: PaperSpace.s) {
                    PaperLabel("Courier (optional)")
                    PaperChips(courierOptions, label: { $0 }, isSelected: { $0 == selectedCourier }) { option in
                        selectedCourier = selectedCourier == option ? "" : option
                    }
                }

                VStack(alignment: .leading, spacing: PaperSpace.xs) {
                    PaperLabel("Notes (optional)")
                    TextField("Anything the next person should know", text: $note, axis: .vertical)
                        .paperType(.body)
                        .foregroundStyle(PaperColor.ink)
                        .lineLimit(3...6)
                        .padding(.bottom, PaperSpace.xs)
                        .overlay(alignment: .bottom) { Rectangle().fill(PaperColor.dot).frame(height: 1) }
                        .accessibilityLabel("Notes")
                }

                Button("Create manifest") {
                    let courier = selectedCourier.isEmpty ? nil : selectedCourier
                    let noteVal = note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
                    onCreate(manifestName, courier, noteVal)
                    dismiss()
                }
                .buttonStyle(.paperPill(.accent, .large, fullWidth: true))
                .disabled(!canCreate)
                .padding(.top, PaperSpace.s)
            }
        }
    }
}
