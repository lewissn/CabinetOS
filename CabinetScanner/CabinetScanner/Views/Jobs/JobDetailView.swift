import CabinetDesign
import SwiftUI

// MARK: - Job Detail
//
// Everything genuinely known about one job. Sections with nothing in them are
// not rendered at all — the brief is explicit that a page of blank fields is
// worse than a short page. Each fact is said once.
//
// Every section that carries ShopVOX information states its provenance, and
// "Open in ShopVOX" is always available rather than appearing only when
// something is missing.

struct JobDetailView: View {
    let jobId: String
    var knownTitle: String?
    var jobTitle: String?

    @StateObject private var viewModel: JobDetailViewModel
    @Environment(\.openURL) private var openURL
    @State private var showingProof = false

    init(jobId: String, knownTitle: String? = nil, jobTitle: String? = nil) {
        self.jobId = jobId
        self.knownTitle = knownTitle
        self.jobTitle = jobTitle
        _viewModel = StateObject(wrappedValue: JobDetailViewModel(jobId: jobId))
    }

    var body: some View {
        PushedScreen(back: "Jobs", onRefresh: { await viewModel.load() }) {
            Group {
                if let detail = viewModel.detail {
                    page(detail)
                } else if let error = viewModel.errorMessage, !viewModel.isLoading {
                    VStack(alignment: .leading, spacing: 0) {
                        if let knownTitle { title(knownTitle) }
                        PaperEmptyState("This job didn't load", message: error, actionTitle: "Try again") {
                            Task { await viewModel.load() }
                        }
                        .section(top: PaperSpace.xxl)
                    }
                } else {
                    // Loading — or nothing loaded, nothing failed, nothing in
                    // flight, which is reachable when the screen is rebuilt for
                    // a different job. Either way: say so and get on with it.
                    VStack(alignment: .leading, spacing: 0) {
                        if let knownTitle { title(knownTitle) }
                        LoadingLine("Loading the job").section(top: PaperSpace.xxl)
                    }
                }
            }
            .screen()
        }
        // Keyed on the job, so a screen reused for a different one reloads
        // rather than keeping the first job's contents.
        .task(id: jobId) { await viewModel.load(jobId: jobId) }
        .sheet(isPresented: $showingProof) {
            if let proof = viewModel.detail?.proof, !proof.isEmpty {
                ProofViewerView(
                    jobId: jobId,
                    jobTitle: knownTitle ?? viewModel.detail?.customer.name ?? "Job",
                    label: proof.displayLabel,
                    externalURL: proof.url
                )
                .paperSheet()
            }
        }
        // The outcome of a workflow action, as a notice rather than an alert:
        // a refusal is information about the step below it, and hiding that
        // step behind a modal to read about it is the wrong way round.
        .safeAreaInset(edge: .bottom) {
            if let result = viewModel.actionResult {
                StepActionBanner(result: result) { viewModel.actionResult = nil }
            }
        }
    }

    // MARK: - Page
    //
    // Ordered for the people who actually open this screen: packaging and
    // post-production, standing at a bench with a job in front of them. They
    // are here to move the step on, look at the proof, and read the order
    // details — so those come first, and everything that answers "whose job is
    // this and where did it come from" comes after.

    private func page(_ detail: JobDetail) -> some View {
        let focus = currentStep(detail)
        let focusIndex = focus.flatMap { f in detail.steps.firstIndex { $0.id == f.id } }
        let everythingDone = detail.focusStep?.isEverythingDone ?? detail.steps.allSatisfy(\.isComplete)

        return VStack(alignment: .leading, spacing: 0) {
            header(detail, focus: focus, focusIndex: focusIndex, everythingDone: everythingDone)

            if !detail.steps.isEmpty {
                StepTrack(steps: detail.steps, currentIndex: everythingDone ? nil : focusIndex)
                    .section(top: PaperSpace.xxl)
            }

            if let focus {
                CurrentStepActions(
                    step: focus,
                    isEverythingDone: everythingDone,
                    isMoving: viewModel.isMoving(focus),
                    isAnyMoving: viewModel.isAnyStepMoving,
                    perform: { action in
                        Task { await viewModel.perform(action, on: focus) }
                    }
                )
                .section(top: PaperSpace.xxl)
            }

            proofSection(detail.proof).section()

            if !detail.dates.isEmpty { datesSection(detail.dates).section() }

            if let items = detail.lineItems, !items.isEmpty { lineItemsSection(items).section() }

            if let instructions = detail.instructions, !instructions.isEmpty {
                instructionsSection(instructions).section()
            }

            // Directly under the workflow facts, because raising one and
            // finishing one are both workflow actions — finishing completes two
            // steps.
            JobConsignmentSection(jobId: jobId).section()

            if !detail.steps.isEmpty {
                stepsSection(detail.steps, capabilities: detail.workflowCapabilities).section()
            }

            if let team = detail.team, !team.isEmpty { teamSection(team).section() }

            if hasMoreFacts(detail) { moreSection(detail).section() }

            if !detail.aliases.isEmpty { aliasesSection(detail.aliases).section() }

            provenanceSection(detail).section()
        }
    }

    // MARK: Header: refs, customer, title, one status line

    private func title(_ text: String) -> some View {
        Text(text)
            .paperType(.largeTitle)
            .foregroundStyle(PaperColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func header(_ detail: JobDetail, focus: JobStep?, focusIndex: Int?, everythingDone: Bool) -> some View {
        let r = detail.references
        let primary = r.salesOrderNumber.map { "SO \($0)" } ?? r.jobNumber.map { "JB \($0)" }
        let customer = detail.customer.name ?? knownTitle ?? "Job"

        return VStack(alignment: .leading, spacing: PaperSpace.s) {
            HStack(spacing: PaperSpace.m) {
                if let primary { Code(primary, color: PaperColor.ink, size: 14) }
                if let shopify = r.shopifyOrderNumber { Code("Shopify #\(shopify)", size: 14) }
            }
            title(customer)
            // The job's title isn't on the detail response; it comes with the
            // row that opened this screen, when there was one.
            if let jobTitle, jobTitle != customer {
                Text(jobTitle).paperType(.bodyL).foregroundStyle(PaperColor.body)
            }
            statusLine(detail, focus: focus, focusIndex: focusIndex, everythingDone: everythingDone)
                .padding(.top, PaperSpace.xs)
        }
        .padding(.top, PaperSpace.s)
    }

    @ViewBuilder
    private func statusLine(_ detail: JobDetail, focus: JobStep?, focusIndex: Int?, everythingDone: Bool) -> some View {
        if everythingDone, !detail.steps.isEmpty {
            StatusText("All \(detail.steps.count) steps done", tone: .done, style: .subhead)
        } else if let focus, let focusIndex {
            StatusText("\(focus.name) · \(focusIndex + 1) of \(detail.steps.count) · \(focus.displayState.lowercased())",
                       tone: focus.tone, style: .subhead)
        } else if let step = detail.production.currentStep {
            StatusText(step, tone: .neutral, style: .subhead)
        }
    }

    /// The step to lead with, as chosen by the server.
    ///
    /// Matched back to our own row by name, which is unique per job. Falls
    /// back to ShopVOX's `currentStepName` only for a response from a deploy
    /// that predates `focusStep` — and that fallback is why the card used to
    /// show a completed step with no action on more than half of all jobs.
    private func currentStep(_ detail: JobDetail) -> JobStep? {
        if let focus = detail.focusStep,
           let match = detail.steps.first(where: { $0.name == focus.name }) {
            return match
        }
        if let name = detail.production.currentStep,
           let match = detail.steps.first(where: { $0.name == name }) {
            return match
        }
        return detail.steps.first { !$0.isComplete } ?? detail.steps.last
    }

    // MARK: - Sections

    @ViewBuilder
    private func proofSection(_ proof: JobProof?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Proof")
            if let proof, !proof.isEmpty {
                Button {
                    showingProof = true
                } label: {
                    PaperRow("View proof", detail: proof.displayLabel, chevron: true)
                }
                .buttonStyle(.plain)
            } else {
                // Roughly one job in twenty has no proof. Saying so plainly
                // beats an absent section, which reads as "still loading".
                Text(proof?.note ?? "No proof has been attached to this job in ShopVOX.")
                    .paperType(.subhead)
                    .foregroundStyle(PaperColor.secondary)
                    .padding(.vertical, PaperSpace.m)
            }
            // ShopVOX gives no approval state, so this says exactly what it is.
            footnote("The proof currently on the job in ShopVOX. Its approval state is not published by the API, so this is not necessarily the approved artwork.")
        }
    }

    private func datesSection(_ d: JobDates) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Despatch")
            // The despatch date leads, in its own weight. It is the one date
            // on this screen that decides what happens on the bench today.
            if let despatch = d.despatchDate ?? d.orderDueDate,
               let date = JobDateFormatting.parse(despatch) {
                HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                    Text(JobDateFormatting.medium(date))
                        .paperType(.title, numeric: true)
                        .foregroundStyle(PaperColor.ink)
                    Spacer(minLength: PaperSpace.m)
                    if let line = DueLine.relative(isoDate: despatch) {
                        StatusText(line.text, tone: line.tone)
                    }
                }
                .padding(.vertical, PaperSpace.s)
                if let sourceLine = despatchSourceLine(d) {
                    Text(sourceLine).paperType(.footnote).foregroundStyle(PaperColor.secondary)
                        .padding(.bottom, PaperSpace.s)
                }
            }

            if let prod = d.productionDueDate, let date = JobDateFormatting.parse(prod) {
                FactRow(label: "Production due", value: JobDateFormatting.medium(date))
            }

            // Shown only when it differs, and labelled as unmaintained. It
            // exists on the order, half the time, and nobody edits it — so
            // presenting it as an equal is how somebody works to the wrong day.
            if let shipping = d.shippingDate,
               shipping != (d.despatchDate ?? d.orderDueDate),
               let date = JobDateFormatting.parse(shipping) {
                FactRow(label: "ShopVOX shipping date", value: JobDateFormatting.medium(date))
            }

            footnote("Despatch is the due date on the order in ShopVOX — the date the office moves when a job is brought forward. It is not a confirmed production schedule."
                     + (d.shippingDate != nil && d.shippingDate != (d.despatchDate ?? d.orderDueDate)
                        ? " ShopVOX also carries a separate \"shipping date\" field. It is not kept up to date here, so nothing works from it."
                        : ""))
        }
    }

    /// Where the despatch date came from and when it was last checked, if the
    /// server says.
    private func despatchSourceLine(_ d: JobDates) -> String? {
        var parts: [String] = []
        if let source = d.despatchDateSource { parts.append("From ShopVOX \(source)") }
        if let seen = JobDateFormatting.relative(fromISO8601: d.despatchDateSeenAt) { parts.append("checked \(seen)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Instructions and contents

    private func instructionsSection(_ instructions: JobInstructions) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Instructions")
            ForEach(instructions.sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: PaperSpace.xs) {
                    Text(section.title).paperType(.label).foregroundStyle(PaperColor.secondary)
                    Text(JobTextFormatting.plain(section.text))
                        .paperType(.body)
                        .foregroundStyle(PaperColor.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.vertical, PaperSpace.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
            }
            footnote("Written on the job in ShopVOX. Formatting is stripped, so check ShopVOX if something reads oddly.")
        }
    }

    private func lineItemsSection(_ items: [JobLineItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("As ordered")
            ForEach(items, id: \.stableId) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                        Text(item.displayName).paperType(.body).foregroundStyle(PaperColor.ink)
                        Spacer(minLength: PaperSpace.m)
                        if let quantity = item.quantityLabel {
                            Text(quantity).paperType(.subhead, numeric: true).foregroundStyle(PaperColor.body)
                        }
                    }
                    if let description = item.description {
                        Text(JobTextFormatting.plain(description))
                            .paperType(.footnote)
                            .foregroundStyle(PaperColor.secondary)
                            .lineLimit(6)
                    }
                }
                .padding(.vertical, PaperSpace.m)
                .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
            }
            footnote("The line items on the ShopVOX order, with the quantities as ordered.")
        }
    }

    private func teamSection(_ t: JobTeam) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Team")
            if let rep = t.salesRep { FactRow(label: "Sales rep", value: rep) }
            if let pm = t.productionManager { FactRow(label: "Production", value: pm) }
            if let designer = t.designer { FactRow(label: "Designer", value: designer) }
        }
    }

    private func stepsSection(_ steps: [JobStep], capabilities: WorkflowCapabilities?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Whole workflow") {
                Text("\(steps.filter(\.isComplete).count) of \(steps.count) done")
                    .paperType(.footnote, numeric: true)
                    .foregroundStyle(PaperColor.tertiary)
            }
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
            VStack(alignment: .leading, spacing: PaperSpace.xs) {
                footnote("Every step on this job. Starting or completing one changes it in ShopVOX — the app shows the result only once ShopVOX confirms it.")
                // Said once, because it is true of the whole job rather than
                // of any one step.
                if let reason = jobWideBlockingReason(steps) {
                    StatusText(reason, tone: .soon).lineLimit(nil)
                }
                if let note = capabilities?.note {
                    // The API's limits, stated rather than met as a dead
                    // button: there is no un-complete and no way to assign.
                    footnote(note)
                }
            }
        }
    }

    /// The reason every step on this job is unmovable, when there is one.
    private func jobWideBlockingReason(_ steps: [JobStep]) -> String? {
        guard !steps.isEmpty, steps.allSatisfy({ !$0.isActionable }) else { return nil }
        return steps.first?.action(.start)?.reason
    }

    // MARK: Everything else, said once

    private func hasMoreFacts(_ d: JobDetail) -> Bool {
        let c = d.customer, r = d.references, p = d.production, l = d.logistics
        return c.postcode != nil || c.contactName != nil || c.contactEmail != nil
            || r.projectNumber != nil || r.customerPo != nil || (r.jobNumber != nil && r.salesOrderNumber != nil)
            || p.currentStage != nil || p.currentStepGroup != nil || p.workflowState != nil || p.daysLeft != nil
            || l.shippingMethod != nil || l.shipToCity != nil
    }

    private func moreSection(_ d: JobDetail) -> some View {
        let c = d.customer, r = d.references, p = d.production, l = d.logistics
        return VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Details")
            if let contact = c.contactName { FactRow(label: "Contact", value: contact) }
            if let email = c.contactEmail {
                FactRow(label: "Email", value: email).textSelection(.enabled)
            }
            if let postcode = c.postcode { FactRow(label: "Postcode", value: postcode) }
            if let method = l.shippingMethod { FactRow(label: "Shipping", value: method) }
            if let city = l.shipToCity { FactRow(label: "Ship to", value: city) }
            // The header shows the sales order (or job number when there is
            // none) and the Shopify order; the rest of the references are here.
            if r.salesOrderNumber != nil, let jb = r.jobNumber { FactRow(label: "Job number", value: jb) }
            if let project = r.projectNumber { FactRow(label: "Project", value: project) }
            if let po = r.customerPo { FactRow(label: "Customer PO", value: po) }
            if let stage = p.currentStage ?? p.currentStepGroup { FactRow(label: "Stage", value: stage) }
            if let state = p.workflowState { FactRow(label: "State", value: state.capitalized) }
            if let days = p.daysLeft {
                // Negative days left is how ShopVOX expresses overdue.
                FactRow(label: days < 0 ? "Overdue by" : "Days left", value: Format.count(abs(days), "day"))
            }
        }
    }

    private func aliasesSection(_ aliases: [JobAlias]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Also known as")
            ForEach(aliases) { alias in
                RowContainer {
                    HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                        VStack(alignment: .leading, spacing: 3) {
                            Code(alias.value, color: PaperColor.ink, size: 14).lineLimit(2)
                            Text(alias.kindLabel).paperType(.caption).foregroundStyle(PaperColor.tertiary)
                        }
                        Spacer(minLength: PaperSpace.m)
                        if alias.needsConfirmation {
                            // A guessed link must never read as an established fact.
                            StatusText("Unconfirmed", tone: .soon, style: .caption)
                        }
                    }
                }
            }
            footnote("Other references that find this job, including the name printed on its panel labels.")
        }
    }

    private func provenanceSection(_ detail: JobDetail) -> some View {
        let p = detail.provenance
        return VStack(alignment: .leading, spacing: PaperSpace.m) {
            PaperSectionHeader("Where this came from") {
                if let relative = JobDateFormatting.relative(fromISO8601: p.capturedAt) {
                    Text(relative).paperType(.footnote).foregroundStyle(PaperColor.tertiary)
                }
            }
            ProvenanceBadge(source: p.dataSource, isStale: p.isStale)
            if p.isStale {
                Text("ShopVOX told us this job changed but not what changed. Open it in ShopVOX for the current state.")
                    .paperType(.footnote)
                    .foregroundStyle(PaperColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let urlString = detail.shopvoxUrl, let url = URL(string: urlString) {
                Button("Open in ShopVOX") { openURL(url) }
                    .buttonStyle(.paperPill(.outline, .regular))
            } else {
                footnote("This job has not been seen by a ShopVOX webhook yet, so there is no direct link to it.")
            }
            footnote("ShopVOX is the source of truth for job status.")
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .paperType(.footnote)
            .foregroundStyle(PaperColor.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, PaperSpace.m)
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

    @State private var confirmingComplete = false

    var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.s) {
            HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.name).paperType(.body).foregroundStyle(PaperColor.ink)
                    if let who = step.assignedToName {
                        Text(who).paperType(.caption).foregroundStyle(PaperColor.secondary).lineLimit(2)
                    } else if let group = step.group {
                        Text(group).paperType(.caption).foregroundStyle(PaperColor.tertiary)
                    }
                }
                Spacer(minLength: PaperSpace.m)
                if isMoving {
                    ProgressView().controlSize(.small).tint(PaperColor.secondary)
                } else {
                    StepStateChip(step: step)
                }
            }

            if let controls = visibleControls, !controls.isEmpty {
                HStack(spacing: PaperSpace.s) {
                    ForEach(controls, id: \.self) { action in
                        Button(action.title) {
                            // Complete asks first, here as on the main button:
                            // it is the one press the app cannot undo.
                            if action == .complete { confirmingComplete = true } else { perform(action) }
                        }
                        .buttonStyle(.paperChip())
                        .disabled(isAnyMoving || !(step.action(action)?.allowed ?? false))
                    }
                }
            }

            // Why nothing can be done — but only when it is about THIS step.
            // A reason that is true of every step on the job (no ShopVOX
            // record, ids not stored yet) is said once under the section
            // instead; repeating it thirteen times is how a footer stops
            // being read.
            if let blocked = perStepReason {
                Text(blocked).paperType(.caption).foregroundStyle(PaperColor.tertiary)
            }
        }
        .padding(.vertical, PaperSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
        .confirmationDialog("Complete \(step.name)?", isPresented: $confirmingComplete, titleVisibility: .visible) {
            Button("Complete \(step.name)") { perform(.complete) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This marks the step done in ShopVOX. It cannot be undone from the app — a step reopened has to be done in ShopVOX itself.")
        }
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

// MARK: - Action outcome

/// The result of the last workflow action.
///
/// Three states, not two. A success ShopVOX confirmed reads as done; a success
/// it accepted but we could not read back says exactly that, because claiming
/// a state we have not seen is how an app and ShopVOX quietly disagree.
private struct StepActionBanner: View {
    let result: StepActionOutcome
    let dismiss: () -> Void

    private var tone: Tone {
        if !result.isSuccess { return .held }
        return result.isConfirmed ? .done : .soon
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
            PaperIcon(result.isSuccess && result.isConfirmed ? .check : .alert, size: 15, lineWidth: 2, color: tone.iconColor)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            Text(result.message)
                .paperType(.subhead)
                .foregroundStyle(PaperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: PaperSpace.s)
            Button(action: dismiss) {
                PaperIcon(.close, size: 12, lineWidth: 2, color: PaperColor.secondary)
            }
            .buttonStyle(.paperIcon)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, PaperSpace.l)
        .padding(.vertical, PaperSpace.xxs)
        .background(tone.soft, in: RoundedRectangle(cornerRadius: 12))
        .background(PaperColor.paper, in: RoundedRectangle(cornerRadius: 12))
        .screen()
        .padding(.bottom, PaperSpace.s)
        .transition(.opacity)
        .animation(PaperMotion.fade, value: result.id)
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

// MARK: - Current step actions
//
// What the job is on now, and the one thing most people came here to do.
//
// The design problem this solves: the workflow list shows thirteen steps, each
// with two small chips, and nothing on the screen said which row mattered.
// People could not find how to update a step at all. Here there is one step,
// named in the status line above, with one 60 pt button for it.
//
// Which action is primary depends on where the step is. A step not yet started
// leads with Start; a step running leads with Finish (Complete in ShopVOX),
// because by the time somebody is looking at a running step on a bench,
// finishing it is what they are about to do. The other action stays
// available, beside it.
//
// Complete asks first. Start and Pause do not. ShopVOX has no way to reopen a
// completed step through the API, so that is the one press here that a person
// cannot undo from the app — and it is a large button at the top of the
// screen, which is exactly where a mis-tap happens.

private struct CurrentStepActions: View {
    let step: JobStep
    /// Whether the whole job is finished. "The next step is below" is not
    /// true of a finished job, and saying it sends somebody scrolling for a
    /// step that does not exist.
    let isEverythingDone: Bool
    let isMoving: Bool
    let isAnyMoving: Bool
    let perform: (StepActionKind) -> Void

    @State private var confirmingComplete = false

    /// The action this step is most likely to need next.
    private var primary: StepActionKind? {
        if allows(.complete), step.isActive { return .complete }
        if allows(.start) { return .start }
        if allows(.complete) { return .complete }
        return nil
    }

    private var secondary: [StepActionKind] {
        StepActionKind.allCases.filter { $0 != primary && allows($0) }
    }

    private func allows(_ action: StepActionKind) -> Bool {
        step.isActionable && (step.action(action)?.allowed ?? false)
    }

    private func title(_ action: StepActionKind) -> String {
        switch action {
        case .start: "Start \(step.name)"
        case .complete: "Finish \(step.name)"
        case .stop: "Pause"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.m) {
            if let primary {
                Button {
                    if primary == .complete { confirmingComplete = true } else { perform(primary) }
                } label: {
                    if isMoving {
                        ProgressView().tint(PaperColor.onAccent)
                    } else {
                        Text(title(primary)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                }
                .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
                .disabled(isAnyMoving)

                if !secondary.isEmpty {
                    HStack(spacing: PaperSpace.m) {
                        ForEach(secondary, id: \.self) { action in
                            Button(action == .complete ? "Finish" : action.title) {
                                if action == .complete { confirmingComplete = true } else { perform(action) }
                            }
                            .buttonStyle(.paperPill(.outline, .regular, fullWidth: true))
                            .disabled(isAnyMoving)
                        }
                    }
                }
            } else if let reason = blockedReason {
                // Nothing to press, and why. A card with no button and no
                // explanation is the fault this screen started with.
                Text(reason)
                    .paperType(.subhead)
                    .foregroundStyle(PaperColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let who = step.assignedToName {
                Text("Assigned to \(who)").paperType(.footnote).foregroundStyle(PaperColor.tertiary)
            }
        }
        .confirmationDialog("Complete \(step.name)?", isPresented: $confirmingComplete, titleVisibility: .visible) {
            Button("Complete \(step.name)") { perform(.complete) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This marks the step done in ShopVOX. It cannot be undone from the app — a step reopened has to be done in ShopVOX itself.")
        }
    }

    private var blockedReason: String? {
        if step.isComplete {
            return isEverythingDone
                ? "Every step on this job is done."
                : "This step is done. The next one is in the workflow below."
        }
        return step.action(.start)?.reason
            ?? "This step cannot be moved from the app."
    }
}
