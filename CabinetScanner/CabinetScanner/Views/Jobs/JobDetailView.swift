import SwiftUI

// MARK: - Job Detail
//
// Everything genuinely known about one job. Sections with nothing in them are
// not rendered at all — the brief is explicit that a page of blank fields is
// worse than a short page.
//
// Every section that carries ShopVOX information states its provenance, and
// "Open in ShopVOX" is always available rather than appearing only when
// something is missing.

struct JobDetailView: View {
    let jobId: String
    var knownTitle: String?

    @StateObject private var viewModel: JobDetailViewModel
    @Environment(\.openURL) private var openURL
    @State private var showingProof = false

    init(jobId: String, knownTitle: String? = nil) {
        self.jobId = jobId
        self.knownTitle = knownTitle
        _viewModel = StateObject(wrappedValue: JobDetailViewModel(jobId: jobId))
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.detail == nil {
                ProgressView("Loading job…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if let error = viewModel.errorMessage, viewModel.detail == nil {
                ContentUnavailableView {
                    Label("Could Not Load", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await viewModel.load() } }
                        .buttonStyle(.borderedProminent)
                }

            } else if let detail = viewModel.detail {
                detailList(detail)
            }
        }
        .navigationTitle(knownTitle ?? "Job")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(isPresented: $showingProof) {
            if let proof = viewModel.detail?.proof, !proof.isEmpty {
                ProofViewerView(
                    jobId: jobId,
                    jobTitle: knownTitle ?? "Job",
                    label: proof.displayLabel,
                    externalURL: proof.url
                )
            }
        }
        // The outcome of a workflow action, as a banner rather than an alert:
        // a refusal is information about the step below it, and hiding that
        // step behind a modal to read about it is the wrong way round.
        .safeAreaInset(edge: .bottom) {
            if let result = viewModel.actionResult {
                StepActionBanner(result: result) { viewModel.actionResult = nil }
            }
        }
    }

    // MARK: - Body

    private func detailList(_ detail: JobDetail) -> some View {
        List {
            provenanceSection(detail.provenance)

            if !detail.customer.isEmpty { customerSection(detail.customer) }
            if !detail.references.isEmpty { referencesSection(detail.references) }
            if !detail.dates.isEmpty { datesSection(detail.dates) }
            if !detail.production.isEmpty { productionSection(detail.production) }
            if let instructions = detail.instructions, !instructions.isEmpty {
                instructionsSection(instructions)
            }
            if let items = detail.lineItems, !items.isEmpty { lineItemsSection(items) }
            proofSection(detail.proof)
            if !detail.steps.isEmpty { stepsSection(detail.steps, capabilities: detail.workflowCapabilities) }
            if !detail.logistics.isEmpty { logisticsSection(detail.logistics) }
            if let team = detail.team, !team.isEmpty { teamSection(team) }
            if !detail.aliases.isEmpty { aliasesSection(detail.aliases) }

            shopvoxSection(detail)
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.load() }
    }

    // MARK: - Sections

    private func provenanceSection(_ p: JobProvenance) -> some View {
        Section {
            HStack {
                ProvenanceBadge(source: p.dataSource, isStale: p.isStale)
                Spacer()
                if let relative = JobDateFormatting.relative(fromISO8601: p.capturedAt) {
                    Text(relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if p.isStale {
                Label(
                    "ShopVOX told us this job changed but not what changed. Open it in ShopVOX for the current state.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Where this came from")
        }
    }

    private func customerSection(_ c: JobCustomer) -> some View {
        Section("Customer") {
            if let name = c.name { DetailRow("Name", name) }
            if let postcode = c.postcode { DetailRow("Postcode", postcode) }
            if let contact = c.contactName { DetailRow("Contact", contact) }
            if let email = c.contactEmail {
                DetailRow("Email", email, isSelectable: true)
            }
        }
    }

    private func referencesSection(_ r: JobReferences) -> some View {
        Section("References") {
            if let so = r.salesOrderNumber { DetailRow("Sales order", so, isMonospaced: true) }
            if let jb = r.jobNumber { DetailRow("Job number", jb, isMonospaced: true) }
            if let project = r.projectNumber { DetailRow("Project", project, isMonospaced: true) }
            if let shopify = r.shopifyOrderNumber { DetailRow("Shopify order", "#\(shopify)", isMonospaced: true) }
            if let po = r.customerPo { DetailRow("Customer PO", po, isMonospaced: true) }
        }
    }

    private func datesSection(_ d: JobDates) -> some View {
        Section {
            // The despatch date leads, in its own weight. It is the one date
            // on this screen that decides what happens on the bench today.
            if let despatch = d.despatchDate ?? d.orderDueDate,
               let date = JobDateFormatting.parse(despatch) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Despatch")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(JobDateFormatting.medium(date))
                        .font(.headline)
                }
            }

            if let prod = d.productionDueDate, let date = JobDateFormatting.parse(prod) {
                DetailRow("Production due", JobDateFormatting.medium(date))
            }

            // Shown only when it differs, and labelled as unmaintained. It
            // exists on the order, half the time, and nobody edits it — so
            // presenting it as an equal is how somebody works to the wrong day.
            if let shipping = d.shippingDate,
               shipping != (d.despatchDate ?? d.orderDueDate),
               let date = JobDateFormatting.parse(shipping) {
                DetailRow("ShopVOX shipping date", JobDateFormatting.medium(date))
            }
        } header: {
            Text("Dates")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Despatch is the due date on the order in ShopVOX — the date the office moves when a job is brought forward. It is not a confirmed production schedule.")
                if d.shippingDate != nil, d.shippingDate != (d.despatchDate ?? d.orderDueDate) {
                    Text("ShopVOX also carries a separate \"shipping date\" field. It is not kept up to date here, so nothing works from it.")
                }
            }
        }
    }

    // MARK: Instructions and contents

    private func instructionsSection(_ instructions: JobInstructions) -> some View {
        Section {
            ForEach(instructions.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(JobTextFormatting.plain(section.text))
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Instructions")
        } footer: {
            Text("Written on the job in ShopVOX. Formatting is stripped, so check ShopVOX if something reads oddly.")
        }
    }

    private func lineItemsSection(_ items: [JobLineItem]) -> some View {
        Section {
            ForEach(items, id: \.stableId) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.displayName)
                            .font(.subheadline)
                        Spacer(minLength: 12)
                        if let quantity = item.quantityLabel {
                            Text(quantity)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                    }
                    if let description = item.description {
                        Text(JobTextFormatting.plain(description))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("On this job")
        } footer: {
            Text("The line items on the ShopVOX order, with the quantities as ordered.")
        }
    }

    private func productionSection(_ p: JobProduction) -> some View {
        Section("Current state") {
            if let step = p.currentStep { DetailRow("Step", step) }
            if let stage = p.currentStage ?? p.currentStepGroup { DetailRow("Stage", stage) }
            if let state = p.workflowState { DetailRow("State", state.capitalized) }
            if let days = p.daysLeft {
                // Negative days left is how ShopVOX expresses overdue.
                DetailRow(
                    days < 0 ? "Overdue by" : "Days left",
                    days < 0 ? "\(abs(days)) days" : "\(days) days"
                )
            }
        }
    }

    private func teamSection(_ t: JobTeam) -> some View {
        Section("Team") {
            if let rep = t.salesRep { DetailRow("Sales rep", rep) }
            if let pm = t.productionManager { DetailRow("Production", pm) }
            if let designer = t.designer { DetailRow("Designer", designer) }
        }
    }

    @ViewBuilder
    private func proofSection(_ proof: JobProof?) -> some View {
        Section {
            if let proof, !proof.isEmpty {
                Button {
                    showingProof = true
                } label: {
                    HStack {
                        Label(proof.displayLabel, systemImage: "doc.richtext")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                // Roughly one job in twenty has no proof. Saying so plainly
                // beats an absent section, which reads as "still loading".
                Label(
                    proof?.note ?? "No proof has been attached to this job in ShopVOX.",
                    systemImage: "doc.badge.ellipsis"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Artwork")
        } footer: {
            // ShopVOX gives no approval state, so this says exactly what it is.
            Text("The proof currently on the job in ShopVOX. Its approval state is not published by the API, so this is not necessarily the approved artwork.")
        }
    }

    private func stepsSection(
        _ steps: [JobStep],
        capabilities: WorkflowCapabilities?
    ) -> some View {
        Section {
            ForEach(steps) { step in
                StepRow(
                    step: step,
                    isMoving: viewModel.isMoving(step),
                    isAnyMoving: viewModel.isAnyStepMoving,
                    perform: { action in
                        Task { await viewModel.perform(action, on: step) }
                    }
                )
            }
        } header: {
            Text("Production steps")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Read from ShopVOX. Starting or completing a step here changes it in ShopVOX — the app shows the result only once ShopVOX confirms it.")

                // Said once, because it is true of the whole job rather than of
                // any one step.
                if let reason = jobWideBlockingReason(steps) {
                    Text(reason)
                        .foregroundStyle(.orange)
                }

                if let note = capabilities?.note {
                    // The API's limits, stated rather than met as a dead
                    // button: there is no un-complete and no way to assign.
                    Text(note)
                }
            }
        }
    }

    /// The reason every step on this job is unmovable, when there is one.
    private func jobWideBlockingReason(_ steps: [JobStep]) -> String? {
        guard !steps.isEmpty, steps.allSatisfy({ !$0.isActionable }) else { return nil }
        return steps.first?.action(.start)?.reason
    }

    private func logisticsSection(_ l: JobLogistics) -> some View {
        Section("Shipping") {
            if let method = l.shippingMethod { DetailRow("Method", method) }
            if let city = l.shipToCity { DetailRow("Ship to", city) }
        }
    }

    private func aliasesSection(_ aliases: [JobAlias]) -> some View {
        Section {
            ForEach(aliases) { alias in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alias.value)
                            .font(.subheadline.monospaced())
                            .lineLimit(2)
                        Text(alias.kindLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if alias.needsConfirmation {
                        // A guessed link must never read as an established fact.
                        Label("Unconfirmed", systemImage: "questionmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Also known as")
        } footer: {
            Text("Other references that find this job, including the name printed on its panel labels.")
        }
    }

    private func shopvoxSection(_ detail: JobDetail) -> some View {
        Section {
            if let urlString = detail.shopvoxUrl, let url = URL(string: urlString) {
                Button {
                    openURL(url)
                } label: {
                    Label("Open in ShopVOX", systemImage: "arrow.up.right.square")
                }
            } else {
                Label(
                    "This job has not been seen by a ShopVOX webhook yet, so there is no direct link to it.",
                    systemImage: "link.badge.plus"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } footer: {
            Text("ShopVOX is the source of truth for job status.")
        }
    }
}

// MARK: - Row

struct DetailRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false
    var isSelectable: Bool = false

    init(_ label: String, _ value: String, isMonospaced: Bool = false, isSelectable: Bool = false) {
        self.label = label
        self.value = value
        self.isMonospaced = isMonospaced
        self.isSelectable = isSelectable
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Group {
                if isSelectable {
                    Text(value).textSelection(.enabled)
                } else {
                    Text(value)
                }
            }
            .font(isMonospaced ? .subheadline.monospaced() : .subheadline)
            .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Step row
//
// One production step, with the controls that move it.
//
// Two rules shape this. A control is disabled with its reason attached rather
// than hidden, because "why can I not complete this?" is the question the
// screen should answer without anyone asking. And exactly one action can be in
// flight at a time across the whole job — the second tap is the mistake, and
// the cheapest place to stop it is before it becomes a request.

private struct StepRow: View {
    let step: JobStep
    let isMoving: Bool
    let isAnyMoving: Bool
    let perform: (StepActionKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.name)
                        .font(.subheadline)
                    if let who = step.assignedToName {
                        Text(who)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if let group = step.group {
                        Text(group)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if isMoving {
                    ProgressView()
                } else {
                    StepStateChip(step: step)
                }
            }

            if let controls = visibleControls, !controls.isEmpty {
                HStack(spacing: 8) {
                    ForEach(controls, id: \.self) { action in
                        StepActionButton(
                            action: action,
                            availability: step.action(action),
                            isDisabled: isAnyMoving,
                            perform: { perform(action) }
                        )
                    }
                }
            }

            // Why nothing can be done — but only when it is about THIS step.
            // A reason that is true of every step on the job (no ShopVOX
            // record, ids not stored yet) is said once under the section
            // instead; repeating it thirteen times is how a footer stops
            // being read.
            if let blocked = perStepReason {
                Text(blocked)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Actions worth putting on screen: the ones that are allowed, plus
    /// nothing else. A row of greyed-out buttons on every completed step is
    /// noise; the reason line below covers that case instead.
    private var visibleControls: [StepActionKind]? {
        guard step.isActionable else { return nil }
        let allowed = StepActionKind.allCases.filter { step.action($0)?.allowed ?? false }
        return allowed.isEmpty ? nil : allowed
    }

    /// A reason that belongs to this step in particular — which, in practice,
    /// means "already complete". Anything that would be identical on every row
    /// is left to the section footer.
    private var perStepReason: String? {
        guard step.isActionable, visibleControls == nil else { return nil }
        return step.action(.complete)?.reason ?? step.action(.start)?.reason
    }
}

private struct StepActionButton: View {
    let action: StepActionKind
    let availability: StepActionAvailability?
    let isDisabled: Bool
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            Label(action.title, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(action == .complete ? .green : .accentColor)
        .disabled(isDisabled || !(availability?.allowed ?? false))
        // Stops a tap on the button from also opening whatever the row is
        // inside — a List row swallows these otherwise.
        .buttonStyle(.bordered)
    }
}

// MARK: - Action outcome

/// The result of the last workflow action.
///
/// Three states, not two. A success ShopVOX confirmed reads as done; a success
/// it accepted but we could not read back says exactly that, because claiming
/// a state we have not seen is how an app and ShopVOX quietly disagree.
private struct StepActionBanner: View {
    let result: StepActionOutcome
    let dismiss: () -> Void

    private var icon: String {
        if !result.isSuccess { return "exclamationmark.triangle.fill" }
        return result.isConfirmed ? "checkmark.circle.fill" : "clock.badge.questionmark"
    }

    private var tint: Color {
        if !result.isSuccess { return .red }
        return result.isConfirmed ? .green : .orange
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(result.message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(tint.opacity(0.35))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeOut(duration: 0.2), value: result.id)
    }
}

// MARK: - Text from ShopVOX

/// ShopVOX stores job notes as HTML from a rich-text editor. Rendering the
/// tags would be wrong and rendering the markup raw is unreadable, so this
/// reduces it to plain text: tags out, entities decoded, block boundaries kept
/// as line breaks so a list of dimensions still reads as a list.
enum JobTextFormatting {

    static func plain(_ html: String) -> String {
        var text = html

        // Block-level boundaries become newlines before the tags are stripped,
        // otherwise every paragraph runs into the next.
        for pattern in ["</p>", "<br>", "<br/>", "<br />", "</div>", "</li>", "</tr>"] {
            text = text.replacingOccurrences(of: pattern, with: "\n", options: .caseInsensitive)
        }

        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }

        // Collapse the runs of blank lines the tag stripping leaves behind.
        text = text.replacingOccurrences(
            of: "\n{3,}", with: "\n\n", options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
