import SwiftUI

struct ManualManifestListView: View {
    @StateObject private var viewModel = ManualManifestListViewModel()

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
                    "No Courier Manifests",
                    systemImage: "truck.box",
                    description: Text("Tap + to create a manual manifest")
                )
            } else {
                List {
                    if !viewModel.openManifests.isEmpty {
                        Section("Open") {
                            ForEach(viewModel.openManifests) { manifest in
                                NavigationLink(value: manifest) {
                                    ManualManifestRow(manifest: manifest)
                                }
                            }
                        }
                    }

                    if !viewModel.finishedManifests.isEmpty {
                        Section("Finished") {
                            ForEach(viewModel.finishedManifests) { manifest in
                                NavigationLink(value: manifest) {
                                    ManualManifestRow(manifest: manifest)
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    await viewModel.loadManifests()
                }
            }
        }
        .navigationTitle("Courier Manifests")
        .navigationDestination(for: ManualManifest.self) { manifest in
            ManualManifestDetailView(
                viewModel: ManualManifestDetailViewModel(manifest: manifest)
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.showCreateSheet) {
            CreateManualManifestSheet { name, courier, note in
                Task { await viewModel.createManifest(name: name, courier: courier, note: note) }
            }
        }
        .overlay(alignment: .bottom) {
            ToastView(message: $viewModel.toastMessage)
        }
        .task {
            await viewModel.loadManifests()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(manifest.manifestName)
                    .font(.headline)

                if let courier = manifest.courier, !courier.isEmpty {
                    Text(courier)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }

            HStack {
                if manifest.isFinished {
                    Label("Finished", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Open", systemImage: "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(manifest.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Manual Manifest Sheet

struct CreateManualManifestSheet: View {
    let onCreate: (String, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var manifestName = ""
    @State private var selectedCourier = ""
    @State private var note = ""

    private let courierOptions = ["", "APC", "ParcelForce", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Manifest") {
                    TextField("Manifest Name", text: $manifestName)
                        .textInputAutocapitalization(.words)
                }

                Section("Courier (optional)") {
                    Picker("Courier", selection: $selectedCourier) {
                        Text("None").tag("")
                        ForEach(courierOptions.filter { !$0.isEmpty }, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Notes (optional)") {
                    TextField("Any additional notes", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Courier Manifest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let courier = selectedCourier.isEmpty ? nil : selectedCourier
                        let noteVal = note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note
                        onCreate(manifestName, courier, noteVal)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(manifestName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
