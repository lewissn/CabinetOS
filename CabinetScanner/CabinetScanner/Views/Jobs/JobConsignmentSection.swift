import SwiftUI

// MARK: - Courier consignment, from the job page
//
// A "manual manifest" is the consignment for one job: one customer, one
// courier, a handful of boxes. 554 of them exist and every one was created by
// typing a name at the bench.
//
// Raising one here fills that name in and links it back to the job, which is
// what lets finishing it move the job on in ShopVOX instead of somebody
// remembering to.
//
// The name is a suggestion, not a rule. It follows the shape the bench has
// been typing — "Dean Crowe - #12740", customer and Shopify order number, the
// form 496 of 530 named consignments already use — and stays editable.

@MainActor
final class JobConsignmentViewModel: ObservableObject {

    @Published private(set) var info: CourierConsignmentInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    /// The finished outcome, kept on screen until dismissed. Completing a step
    /// in ShopVOX cannot be undone, so what happened must be readable.
    @Published var finishResult: CourierConsignmentFinished?

    @Published var name: String = ""
    @Published var courier: String = ""

    private let jobId: String
    private let service: JobIndexService

    /// What the bench actually uses, by volume: APC on 504 of 554.
    let couriers = ["APC", "Collection", "Other"]

    init(jobId: String, service: JobIndexService = JobIndexService()) {
        self.jobId = jobId
        self.service = service
    }

    var openConsignment: CourierConsignment? { info?.openConsignment }
    var existing: [CourierConsignment] { info?.existing ?? [] }
    var canCompleteSteps: Bool { info?.canCompleteSteps ?? false }

    func load() async {
        isLoading = true
        do {
            let loaded = try await service.consignmentInfo(jobId: jobId)
            info = loaded
            if name.isEmpty { name = loaded.suggestedName }
            if courier.isEmpty {
                // Match the ShopVOX shipping method to a courier we use, and
                // otherwise leave it for the person to choose rather than
                // guessing at a carrier.
                courier = couriers.first {
                    loaded.suggestedCourier?.localizedCaseInsensitiveContains($0) == true
                } ?? ""
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func create() async {
        guard !isWorking, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isWorking = true
        errorMessage = nil

        do {
            let created = try await service.createConsignment(
                jobId: jobId,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                courier: courier.isEmpty ? nil : courier,
                note: nil
            )
            if !created.ok { errorMessage = created.error ?? "Could not raise the consignment." }
            await load()
        } catch {
            errorMessage = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }

        isWorking = false
    }

    func finish(_ consignment: CourierConsignment) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil

        do {
            finishResult = try await service.finishConsignment(jobId: jobId, manifestId: consignment.id)
            await load()
        } catch {
            errorMessage = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }

        isWorking = false
    }
}

struct JobConsignmentSection: View {
    @StateObject private var viewModel: JobConsignmentViewModel
    @State private var confirmingFinish: CourierConsignment?
    /// Raising one is hidden behind a disclosure until asked for — most visits
    /// to this screen are not about starting a courier shipment.
    @State private var isRaising = false

    init(jobId: String) {
        _viewModel = StateObject(wrappedValue: JobConsignmentViewModel(jobId: jobId))
    }

    var body: some View {
        Section {
            ForEach(viewModel.existing) { consignment in
                CourierConsignmentRow(
                    consignment: consignment,
                    isWorking: viewModel.isWorking,
                    finish: { confirmingFinish = consignment }
                )
            }

            if isRaising {
                raiseForm
            } else {
                Button {
                    isRaising = true
                } label: {
                    Label(
                        viewModel.existing.isEmpty
                            ? "Raise courier consignment"
                            : "Raise another consignment",
                        systemImage: "shippingbox.and.arrow.backward"
                    )
                }
                .disabled(viewModel.isLoading)
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let result = viewModel.finishResult {
                FinishOutcome(result: result) { viewModel.finishResult = nil }
            }
        } header: {
            Text("Courier consignment")
        } footer: {
            footerText
        }
        .task { await viewModel.load() }
        .confirmationDialog(
            "Finish this consignment?",
            isPresented: Binding(
                get: { confirmingFinish != nil },
                set: { if !$0 { confirmingFinish = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingFinish
        ) { consignment in
            Button("Finish and complete the job") {
                Task { await viewModel.finish(consignment) }
                confirmingFinish = nil
            }
            Button("Cancel", role: .cancel) { confirmingFinish = nil }
        } message: { _ in
            Text(
                viewModel.canCompleteSteps
                    ? "This closes the consignment and completes Pack & Wrap and then Despatch in ShopVOX. Neither can be undone from the app, and completing Despatch drafts the customer's despatch email."
                    : "This closes the consignment. There is no ShopVOX job behind this record, so no step will be completed."
            )
        }
    }

    @ViewBuilder
    private var raiseForm: some View {
        // Named after the customer and their order, because that is how these
        // get searched for afterwards.
        TextField("Consignment name", text: $viewModel.name)
            .autocorrectionDisabled()

        Picker("Courier", selection: $viewModel.courier) {
            Text("Not set").tag("")
            ForEach(viewModel.couriers, id: \.self) { Text($0).tag($0) }
        }

        if let open = viewModel.openConsignment {
            // A job can legitimately ship in two parts, so this warns rather
            // than blocks — but nobody should raise a second by accident.
            Label(
                "\"\(open.manifestName)\" is already open for this job. Raising another is fine if it is shipping in two parts.",
                systemImage: "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }

        HStack {
            Button {
                Task {
                    await viewModel.create()
                    if viewModel.errorMessage == nil { isRaising = false }
                }
            } label: {
                if viewModel.isWorking {
                    ProgressView()
                } else {
                    Text("Raise consignment")
                }
            }
            .disabled(viewModel.isWorking || viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer()

            Button("Cancel") { isRaising = false }
                .foregroundStyle(.secondary)
        }
    }

    private var footerText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Boxes are packed against the consignment in the Packaging tab.")
            if viewModel.canCompleteSteps {
                Text("Finishing it completes Pack & Wrap and then Despatch in ShopVOX.")
            } else if viewModel.info != nil {
                Text("This record has no ShopVOX job behind it, so finishing a consignment will not complete any step.")
            }
        }
    }
}

// MARK: - Rows

private struct CourierConsignmentRow: View {
    let consignment: CourierConsignment
    let isWorking: Bool
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(consignment.manifestName)
                        .font(.subheadline.weight(.medium))
                    if let courier = consignment.courier {
                        Text(courier)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if consignment.isOpen {
                    Label("Open", systemImage: "circle")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                } else {
                    Label("Finished", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            if consignment.isOpen {
                Button(action: finish) {
                    Label("Finish consignment", systemImage: "checkmark.seal")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isWorking)
            } else if consignment.hasMovedTheJobOn {
                Text("Completed the job's steps in ShopVOX.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// What ShopVOX did about each step. Shown per step rather than as one verdict:
/// "Pack & Wrap done, Despatch refused" is the case somebody has to act on.
private struct FinishOutcome: View {
    let result: CourierConsignmentFinished
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(result.message ?? (result.stepsCompleted == true ? "Done." : "Finished."))
                        .font(.caption)
                } icon: {
                    Image(systemName: result.stepsCompleted == true
                          ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(result.stepsCompleted == true ? .green : .orange)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.caption2) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            ForEach(result.steps ?? []) { step in
                HStack(spacing: 6) {
                    Image(systemName: step.ok ? "checkmark" : "xmark")
                        .font(.caption2)
                        .foregroundStyle(step.ok ? .green : .red)
                    Text(step.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
