import CabinetDesign
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

    let jobId: String
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
            let result = try await service.finishConsignment(jobId: jobId, manifestId: consignment.id)
            finishResult = result
            if result.ok, result.finished != false {
                // No box count on this page, so the moment claims none.
                MomentCenter.shared.play(FinishMoment(
                    name: consignment.manifestName,
                    boxCount: nil,
                    movedJobOn: result.stepsCompleted == true && result.alreadyCompleted != true
                ))
            } else {
                HapticService.error()
            }
            await load()
        } catch {
            errorMessage = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }

        isWorking = false
    }
}

// MARK: - One model for the page
//
// The quick action at the top of the job page and the section further down
// show the same consignments, so they share one view model: raising one at
// the top shows in the section straight away.

/// Owns the job's consignment model and hands it to everything below.
/// Keyed on the job, so a page reused for another job starts afresh.
struct JobConsignmentScope<Content: View>: View {
    @StateObject private var viewModel: JobConsignmentViewModel
    @ViewBuilder var content: () -> Content

    init(jobId: String, @ViewBuilder content: @escaping () -> Content) {
        _viewModel = StateObject(wrappedValue: JobConsignmentViewModel(jobId: jobId))
        self.content = content
    }

    var body: some View {
        content()
            .environmentObject(viewModel)
            .task { await viewModel.load() }
            .onReceive(NotificationCenter.default.publisher(for: .courierConsignmentsChanged)) { _ in
                Task { await viewModel.load() }
            }
    }
}

// MARK: - Quick action, near the top

/// "Raise courier consignment", as a button you can't miss, under the step
/// action. Once one is open it becomes "Pack boxes", straight to its boxes.
struct CourierQuickAction: View {
    @EnvironmentObject private var viewModel: JobConsignmentViewModel
    @State private var showingRaise = false
    @State private var packing: ManualManifest?

    var body: some View {
        Group {
            if let open = viewModel.openConsignment {
                VStack(alignment: .leading, spacing: PaperSpace.xs) {
                    Button {
                        packing = open.manualManifest(jobId: viewModel.jobId)
                    } label: {
                        Label { Text("Pack boxes") } icon: { PaperIcon(.box, size: 18, color: PaperColor.paper) }
                    }
                    .buttonStyle(.paperPill(.ink, .large, fullWidth: true))
                    Text("\(open.manifestName)\(open.courier.map { " · \($0)" } ?? "") is open")
                        .paperType(.footnote)
                        .foregroundStyle(PaperColor.secondary)
                        .lineLimit(1)
                }
            } else if viewModel.info != nil {
                Button {
                    showingRaise = true
                } label: {
                    Label { Text("Raise courier consignment") } icon: { PaperIcon(.truck, size: 18) }
                }
                .buttonStyle(.paperPill(.outline, .large, fullWidth: true))
            }
        }
        .sheet(isPresented: $showingRaise) {
            RaiseConsignmentSheet { created in
                showingRaise = false
                // Straight on to packing it.
                if created { packing = viewModel.openConsignment?.manualManifest(jobId: viewModel.jobId) }
            }
            .environmentObject(viewModel)
            .paperSheet(detents: [.medium, .large])
        }
        .navigationDestination(item: $packing) { manifest in
            ManualManifestScreen(manifest: manifest, backLabel: "Job")
        }
    }
}

// MARK: - Raise sheet

struct RaiseConsignmentSheet: View {
    @EnvironmentObject private var viewModel: JobConsignmentViewModel
    /// Called with true once a consignment has been raised.
    let onDone: (Bool) -> Void

    private var canRaise: Bool {
        !viewModel.isWorking && !viewModel.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        SheetScreen("Courier consignment") {
            VStack(alignment: .leading, spacing: PaperSpace.xl) {
                // Named after the customer and their order, because that is
                // how these get searched for afterwards.
                PaperUnderlineField("Consignment name", text: $viewModel.name)
                    .autocorrectionDisabled()
                    .padding(.top, PaperSpace.l)

                VStack(alignment: .leading, spacing: PaperSpace.s) {
                    PaperLabel("Courier")
                    PaperChips(viewModel.couriers, label: { $0 }, isSelected: { $0 == viewModel.courier }) { option in
                        viewModel.courier = viewModel.courier == option ? "" : option
                    }
                }

                if let open = viewModel.openConsignment {
                    // A job can legitimately ship in two parts, so this warns
                    // rather than blocks — but nobody should raise a second by
                    // accident.
                    Notice(
                        text: "\u{201C}\(open.manifestName)\u{201D} is already open for this job. Raising another is fine if it's shipping in two parts.",
                        tone: .soon
                    )
                }

                if let error = viewModel.errorMessage {
                    Notice(text: error, tone: .held)
                }

                Button {
                    Task {
                        await viewModel.create()
                        if viewModel.errorMessage == nil { onDone(true) }
                    }
                } label: {
                    if viewModel.isWorking {
                        ProgressView().tint(PaperColor.onAccent)
                    } else {
                        Text("Raise and start packing")
                    }
                }
                .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
                .disabled(!canRaise)

                Text(viewModel.canCompleteSteps
                     ? "Finishing it later completes Pack & Wrap and then Despatch in ShopVOX."
                     : "Boxes are packed against it in the Packing tab.")
                    .paperType(.footnote)
                    .foregroundStyle(PaperColor.tertiary)
            }
        }
    }
}

// MARK: - The section, further down

struct JobConsignmentSection: View {
    @EnvironmentObject private var viewModel: JobConsignmentViewModel
    @State private var confirmingFinish: CourierConsignment?
    @State private var showingRaise = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Courier consignment")

            ForEach(viewModel.existing) { consignment in
                CourierConsignmentRow(
                    consignment: consignment,
                    jobId: viewModel.jobId,
                    isWorking: viewModel.isWorking,
                    finish: { confirmingFinish = consignment }
                )
            }

            if viewModel.existing.isEmpty, viewModel.info != nil {
                Text("None yet. Raise one from the button at the top of the page.")
                    .paperType(.subhead)
                    .foregroundStyle(PaperColor.secondary)
                    .padding(.vertical, PaperSpace.s)
            } else if !viewModel.existing.isEmpty {
                // A second one, for a job shipping in two parts.
                Button("Raise another consignment") { showingRaise = true }
                    .buttonStyle(.paperText(PaperColor.ink, .subhead, weight: .semibold))
                    .disabled(viewModel.isLoading)
                    .padding(.top, PaperSpace.xs)
            }

            if let error = viewModel.errorMessage, !showingRaise {
                Notice(text: error, tone: .soon).padding(.top, PaperSpace.m)
            }

            if let result = viewModel.finishResult {
                FinishOutcome(result: result) { viewModel.finishResult = nil }
                    .padding(.top, PaperSpace.m)
            }

            footerText.padding(.top, PaperSpace.m)
        }
        .sheet(isPresented: $showingRaise) {
            RaiseConsignmentSheet { _ in showingRaise = false }
                .environmentObject(viewModel)
                .paperSheet(detents: [.medium, .large])
        }
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

    private var footerText: some View {
        VStack(alignment: .leading, spacing: PaperSpace.xs) {
            Text("Boxes are packed against the consignment in the Packing tab.")
            if viewModel.canCompleteSteps {
                Text("Finishing it completes Pack & Wrap and then Despatch in ShopVOX.")
            } else if viewModel.info != nil {
                Text("This record has no ShopVOX job behind it, so finishing a consignment will not complete any step.")
            }
        }
        .paperType(.footnote)
        .foregroundStyle(PaperColor.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension CourierConsignment {
    /// The consignment as the Packing tab knows it, linked to its job so
    /// finishing it there moves the job on too.
    func manualManifest(jobId: String) -> ManualManifest {
        let created = createdAt.flatMap {
            ISO8601DateFormatter.withFractions.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
        } ?? Date()
        var m = ManualManifest(
            id: id,
            manifestName: manifestName,
            courier: courier,
            status: isOpen ? .open : .finished,
            note: nil,
            createdAt: created,
            updatedAt: created
        )
        m.jobIndexId = jobId
        return m
    }
}

// MARK: - Rows

private struct CourierConsignmentRow: View {
    let consignment: CourierConsignment
    let jobId: String
    let isWorking: Bool
    let finish: () -> Void

    private var manifest: ManualManifest { consignment.manualManifest(jobId: jobId) }

    var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.s) {
            HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(consignment.manifestName).paperType(.body).foregroundStyle(PaperColor.ink)
                    if let courier = consignment.courier {
                        Text(courier).paperType(.footnote).foregroundStyle(PaperColor.secondary)
                    }
                }
                Spacer(minLength: PaperSpace.m)
                StatusText(consignment.isOpen ? "Open" : "Finished", tone: consignment.isOpen ? .progress : .done)
            }

            if consignment.isOpen {
                HStack(spacing: PaperSpace.m) {
                    // Straight to its boxes, rather than finding it again in
                    // the Packing tab.
                    NavigationLink {
                        ManualManifestScreen(manifest: manifest, backLabel: "Job")
                    } label: {
                        Text("Pack boxes")
                    }
                    .buttonStyle(.paperPill(.ink, .compact))
                    Button("Finish consignment", action: finish)
                        .buttonStyle(.paperPill(.outline, .compact))
                        .disabled(isWorking)
                }
            } else if consignment.hasMovedTheJobOn {
                Text("Completed the job's steps in ShopVOX.")
                    .paperType(.caption)
                    .foregroundStyle(PaperColor.tertiary)
            }
        }
        .padding(.vertical, PaperSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
    }
}

/// What ShopVOX did about each step. Shown per step rather than as one verdict:
/// "Pack & Wrap done, Despatch refused" is the case somebody has to act on.
private struct FinishOutcome: View {
    let result: CourierConsignmentFinished
    let dismiss: () -> Void

    private var tone: Tone { result.stepsCompleted == true ? .done : .soon }

    var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.s) {
            HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                StatusText(result.message ?? (result.stepsCompleted == true ? "Done." : "Finished."), tone: tone, style: .subhead, lineLimit: nil)
                Spacer(minLength: PaperSpace.s)
                Button(action: dismiss) {
                    PaperIcon(.close, size: 12, lineWidth: 2, color: PaperColor.secondary)
                }
                .buttonStyle(.paperIcon)
                .accessibilityLabel("Dismiss")
            }
            ForEach(result.steps ?? []) { step in
                StatusText(step.message, tone: step.ok ? .done : .held, style: .footnote, lineLimit: nil)
            }
        }
        .padding(.leading, PaperSpace.l)
        .padding(.vertical, PaperSpace.s)
        .background(tone.soft, in: RoundedRectangle(cornerRadius: 12))
    }
}

private extension ISO8601DateFormatter {
    static let withFractions: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
