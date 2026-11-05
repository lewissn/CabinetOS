import CabinetDesign
import PhotosUI
import SwiftUI

// MARK: - Fitting kit
//
// The person picking a job's fittings reads what's needed, ticks items as they
// go, and finishes with a photo of the parts. Ticks show at once and survive a
// dropped connection (KitPickQueue). Finishing is separate and deliberate: it
// completes the job's ShopVOX step, which can't be undone.

struct FittingKitView: View {
    let jobId: String
    var jobTitle: String?
    var backLabel: String = "Job"
    /// What the station's queue already knew about the job.
    private var known: KitLink?
    /// Beside the queue on a wide screen: no back bar.
    private var embedded = false
    /// Offered once this kit is finished.
    private var next: KitNext?
    private var onFinished: (() -> Void)?

    @StateObject private var viewModel: FittingKitViewModel
    @ObservedObject private var queue = KitPickQueue.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingPicked = false
    /// Just ticked: stays where it is for a moment before folding away, so the
    /// list doesn't jump under the picker's finger and a wrong tick is easy to undo.
    @State private var lingering: Set<String> = []
    @State private var itemSheet: KitItemSheet?
    @State private var clearingShortage: KitShortage?
    @State private var viewingPhoto: KitPhoto?
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var confirmingFinish = false

    init(jobId: String, jobTitle: String? = nil, backLabel: String = "Job") {
        self.jobId = jobId
        self.jobTitle = jobTitle
        self.backLabel = backLabel
        _viewModel = StateObject(wrappedValue: FittingKitViewModel(jobId: jobId))
    }

    /// From a station's queue.
    init(link: KitLink, backLabel: String = "Stations", embedded: Bool = false,
         next: KitNext? = nil, onFinished: (() -> Void)? = nil) {
        self.init(jobId: link.jobId, jobTitle: link.title, backLabel: backLabel)
        known = link
        self.embedded = embedded
        self.next = next
        self.onFinished = onFinished
    }

    private var picking: KitPicking? { queue.displayed(jobId: jobId) }
    private var customer: String? { viewModel.detail?.customer.name ?? jobTitle }
    private var salesOrder: String? { viewModel.detail?.references.salesOrderNumber ?? known?.salesOrder }
    private var despatchDate: String? {
        viewModel.detail.flatMap { $0.dates.despatchDate ?? $0.dates.orderDueDate } ?? known?.despatchDate
    }
    private var carrier: String? { known?.carrier ?? viewModel.detail?.logistics.shippingMethod }
    /// Polled only while somebody can see it.
    private var isWatching: Bool { scenePhase == .active && viewModel.response != nil }
    private var isWide: Bool { sizeClass == .regular }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// "Danielle Tucker (SO 12056)", for confirmations that have to name the job.
    private var jobName: String {
        switch (customer, salesOrder) {
        case let (name?, so?): "\(name) (SO \(so))"
        case let (name?, nil): name
        case let (nil, so?): "SO \(so)"
        case (nil, nil): "this job"
        }
    }

    var body: some View {
        frame
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .task(id: jobId) { await viewModel.load() }
        // Ticks from another device (Lewis's phone, the station iPad) show
        // here within half a minute.
        .task(id: isWatching) {
            guard isWatching else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await viewModel.refresh()
            }
        }
        .onChange(of: viewModel.finishedCount) { _, _ in onFinished?() }
        .onResume { await viewModel.load() }
        // The server says the kit changed under the picker: read it again.
        .onChange(of: queue.kitChanges[jobId]) { _, _ in
            Task { await viewModel.load() }
        }
        // Ticks closed a shortage: read the open ones again.
        .onChange(of: queue.shortageChanges[jobId]) { _, _ in
            Task { await viewModel.load() }
        }
        .safeAreaInset(edge: .bottom) {
            if let outcome = viewModel.outcome {
                StepActionBanner(result: outcome) { viewModel.outcome = nil }
            }
        }
        // One sheet for both, so "Not enough" in the count sheet swaps it for
        // the shortage sheet.
        .sheet(item: $itemSheet) { sheet in
            switch sheet {
            case .count(let item):
                KitCountSheet(item: item,
                              onSet: { viewModel.setCount($0, for: item) },
                              onNotEnough: { itemSheet = .shortage(item) })
                    .paperSheet(detents: [.medium, .large])
            case .shortage(let item):
                KitShortageSheet(item: item, existing: viewModel.shortage(for: item)) { short, note in
                    await viewModel.reportShortage(item, short: short, note: note)
                }
                .paperSheet(detents: [.large])
            }
        }
        .confirmationDialog(clearTitle,
                            isPresented: Binding(get: { clearingShortage != nil },
                                                 set: { if !$0 { clearingShortage = nil } }),
                            titleVisibility: .visible,
                            presenting: clearingShortage) { shortage in
            Button("Clear shortage", role: .destructive) {
                Task { await viewModel.clearShortage(shortage) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It comes off Cabinet Lab. Ticking the item as fully picked clears it too.")
        }
        .sheet(item: $viewingPhoto) { photo in
            KitPhotoSheet(jobId: jobId, photo: photo, jobName: jobName) {
                Task { await viewModel.delete(photo) }
            }
            .paperSheet()
        }
        .fullScreenCover(isPresented: $showingCamera) {
            KitCameraView { image in
                showingCamera = false
                if let image { Task { await viewModel.upload(image) } }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showingLibrary, selection: $libraryItem, matching: .images)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await viewModel.upload(image)
                }
            }
        }
    }

    @ViewBuilder
    private var frame: some View {
        let page = VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        if embedded {
            ScrollView {
                page.screen().padding(.bottom, PaperSpace.xxl)
            }
            .refreshable { await viewModel.load() }
            .paperBackground()
        } else {
            PushedScreen(back: backLabel, onRefresh: { await viewModel.load() }) {
                page.screen()
            }
        }
    }

    private var finishMessage: String {
        var parts: [String] = []
        if let picking, !picking.complete {
            let short = picking.counts.items - picking.counts.done
            if short > 0 { parts.append("\(Format.count(short, "item")) not fully picked.") }
            if !picking.orphans.isEmpty { parts.append("Some parts still need taking out of the box.") }
        }
        if !viewModel.shortages.isEmpty {
            parts.append("\(Format.count(viewModel.shortages.count, "item")) reported short: finishing leaves \(viewModel.shortages.count == 1 ? "it" : "them") on Cabinet Lab to order.")
        }
        if viewModel.photos.isEmpty { parts.append("No photo has been added.") }
        parts.append("This marks the step done in ShopVOX. It can't be undone from the app.")
        return parts.joined(separator: " ")
    }

    private var clearTitle: String {
        guard let shortage = clearingShortage else { return "Clear this shortage?" }
        let name = shortage.label ?? picking?.items.first(where: { $0.key == shortage.key })?.label ?? "this item"
        return "Clear the shortage of \(name)?"
    }

    private func finish() {
        Task { await viewModel.perform(.complete) }
    }

    private func addPhoto() {
        if cameraAvailable { showingCamera = true } else { showingLibrary = true }
    }

    // MARK: - Header

    /// Whose kit, and when it goes: the two things a picker checks first.
    private var header: some View {
        VStack(alignment: .leading, spacing: PaperSpace.s) {
            HStack(spacing: PaperSpace.m) {
                Text("Fitting kit").paperType(.label).foregroundStyle(PaperColor.secondary)
                if let salesOrder { Code("SO \(salesOrder)", color: PaperColor.ink, size: 14) }
            }
            Text(customer ?? "Fitting kit")
                .paperType(.largeTitle)
                .foregroundStyle(PaperColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: PaperSpace.s) {
                if let due = DueLine.make(isoDate: despatchDate) {
                    StatusText(due.text, tone: due.tone, style: .subhead)
                }
                if let carrier {
                    Text(carrier).paperType(.subhead).foregroundStyle(PaperColor.secondary).lineLimit(1)
                }
                if let step = viewModel.kitStep, step.isActive || step.isHalted {
                    StatusText(step.isActive ? "Picking" : "Paused", tone: .progress, style: .subhead)
                }
            }
        }
        .padding(.top, embedded ? PaperSpace.xl : PaperSpace.s)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let response = viewModel.response {
            loaded(response)
        } else if let error = viewModel.errorMessage, !viewModel.isLoading {
            PaperEmptyState("The kit didn't load", message: error, actionTitle: "Try again") {
                Task { await viewModel.load() }
            }
            .section(top: PaperSpace.xxl)
        } else {
            LoadingLine("Loading the kit").section(top: PaperSpace.xxl)
        }
    }

    @ViewBuilder
    private func loaded(_ response: FittingKitResponse) -> some View {
        if let error = viewModel.errorMessage {
            Notice(text: "This may be out of date. \(error)", tone: .soon).section(top: PaperSpace.l)
        }
        if let problem = response.kitProblem {
            Notice(text: problem, tone: .soon).section(top: PaperSpace.l)
        }
        if let problem = response.pickingProblem {
            Notice(text: problem, tone: .soon).section(top: PaperSpace.l)
        }
        if let problem = response.shortagesProblem {
            Notice(text: problem, tone: .soon).section(top: PaperSpace.l)
        }
        if let problem = viewModel.shortageProblem {
            Notice(text: problem, tone: .soon).section(top: PaperSpace.l)
        }
        sendState

        if let picking {
            orphans(picking.orphans)
            pickList(picking.items)
            photosSection.section()
            stepSection(picking).section()
        } else if let kit = response.kit {
            // No picking on the server yet: the list can still be read.
            readOnlyList(kit)
            stepSection(nil).section()
        } else if let need = response.need, need.isNotNeeded {
            PaperEmptyState(need.label, message: need.detail)
                .section(top: PaperSpace.xxl)
            stepSection(nil).section()
        } else if response.kitProblem == nil {
            PaperEmptyState("No fitting kit yet",
                            message: "Add this job's fittings list or ERP export on its page on the Cabinet Lab website, and the kit appears here.")
                .section(top: PaperSpace.xxl)
        }
    }

    /// Only once sending has actually failed: a tick on its way isn't news.
    @ViewBuilder
    private var sendState: some View {
        if let problem = queue.problems[jobId] {
            let waiting = queue.waitingCount(jobId: jobId)
            if waiting > 0 {
                Notice(text: "\(Format.count(waiting, "change")) waiting to send. \(problem)", tone: .soon,
                       action: "Send now") {
                    Task { await queue.flush(jobId: jobId) }
                }
                .section(top: PaperSpace.l)
            } else {
                Notice(text: problem, tone: .soon).section(top: PaperSpace.l)
            }
        }
    }

    // MARK: - The bar along the bottom

    /// How far the kit has got and the way to finish it, always in reach:
    /// before, Finish was at the very end of a long list.
    @ViewBuilder
    private var bottomBar: some View {
        if let picking, viewModel.response != nil {
            let step = viewModel.kitStep
            VStack(spacing: 0) {
                PaperBar(picking.counts.items > 0 ? Double(picking.counts.done) / Double(picking.counts.items) : 0,
                         color: picking.complete ? PaperColor.success : PaperColor.accent, track: PaperColor.segment, height: 4)
                    .frame(height: 4)
                HStack(spacing: PaperSpace.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(picking.complete ? "All picked" : "\(PaperFormat.int(picking.counts.done)) of \(Format.count(picking.counts.items, "item")) picked")
                            .paperType(.headline, numeric: true)
                            .foregroundStyle(picking.complete ? PaperColor.success : PaperColor.ink)
                        if let barDetail {
                            Text(barDetail).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary)
                        }
                    }
                    Spacer(minLength: PaperSpace.m)
                    if let step {
                        if step.isComplete {
                            if let next {
                                Button("Next: \(next.name)", action: next.open)
                                    .buttonStyle(.paperPill(.accent, .regular))
                                    .lineLimit(1)
                            } else {
                                StatusText("Finished", tone: .done, style: .subhead)
                            }
                        } else {
                            finishButton(step, picking: picking)
                        }
                    }
                }
                .padding(.vertical, PaperSpace.m)
                .screen()
            }
            .background(PaperColor.surface.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { PaperHairline(color: PaperColor.hairlineSoft) }
        }
    }

    /// "1 short · 2 photos"
    private var barDetail: String? {
        var parts: [String] = []
        if !viewModel.shortages.isEmpty { parts.append("\(PaperFormat.int(viewModel.shortages.count)) short") }
        parts.append(viewModel.photos.isEmpty ? "No photo yet" : Format.count(viewModel.photos.count, "photo"))
        if let picking, !picking.orphans.isEmpty { parts.append("\(Format.count(picking.orphans.count, "part")) to take out") }
        return parts.joined(separator: " · ")
    }

    private func finishButton(_ step: JobStep, picking: KitPicking) -> some View {
        let canFinish = step.isActionable && step.action(.complete)?.allowed == true
        // Finish leads once there's nothing left to pick. Before that it's
        // there without being the obvious tap.
        return Button {
            confirmingFinish = true
        } label: {
            if viewModel.isMovingStep {
                ProgressView().tint(picking.complete ? PaperColor.onAccent : PaperColor.ink)
            } else {
                Text("Finish kit")
            }
        }
        .buttonStyle(.paperPill(picking.complete ? .accent : .outline, isWide ? .floor : .regular))
        .disabled(!canFinish || viewModel.isMovingStep)
        .confirmationDialog("Finish the fitting kit for \(jobName)?", isPresented: $confirmingFinish, titleVisibility: .visible) {
            if viewModel.photos.isEmpty {
                Button("Add a photo first") { addPhoto() }
                Button("Finish without a photo") { finish() }
            } else {
                Button("Finish fitting kit") { finish() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(finishMessage)
        }
    }

    // MARK: - Leftovers

    @ViewBuilder
    private func orphans(_ orphans: [KitOrphan]) -> some View {
        if !orphans.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PaperSectionHeader("Take these out")
                Notice(text: "These were picked earlier but aren't on the kit any more. The fittings list has changed.", tone: .held)
                    .padding(.vertical, PaperSpace.s)
                ForEach(orphans) { orphan in
                    HStack(spacing: PaperSpace.m) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(orphan.displayName).paperType(.body).foregroundStyle(PaperColor.ink)
                            Text("\(PaperFormat.int(orphan.picked)) in the box").paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary)
                        }
                        Spacer(minLength: PaperSpace.m)
                        Button("Mark taken out") { viewModel.takenOut(orphan) }
                            .buttonStyle(.paperPill(.outline, .compact))
                    }
                    .padding(.vertical, PaperSpace.m)
                    .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
                }
            }
            .section(top: PaperSpace.xxl)
        }
    }

    // MARK: - The list

    @ViewBuilder
    private func pickList(_ items: [KitPickItem]) -> some View {
        let toPick = items.filter { !$0.done || lingering.contains($0.key) }
        let picked = items.filter { $0.done && !lingering.contains($0.key) }
        if toPick.isEmpty, !items.isEmpty {
            Notice(text: viewModel.photos.isEmpty
                   ? "Everything's picked. Add a photo of the parts, then finish the kit."
                   : "Everything's picked. Finish the kit when it's packed.",
                   tone: .progress, action: viewModel.photos.isEmpty ? "Add photo" : nil) { addPhoto() }
                .section(top: PaperSpace.xl)
        }
        toPickList(toPick)
        if !picked.isEmpty { pickedList(picked) }
    }

    private func pickedList(_ items: [KitPickItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showingPicked.toggle() }
            } label: {
                PaperSectionHeader("Picked (\(PaperFormat.int(items.count)))") {
                    PaperIcon(showingPicked ? .chevronDown : .chevronRight, size: 12, color: PaperColor.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showingPicked ? "Hides the picked items" : "Shows the picked items")
            if showingPicked {
                ForEach(items) { item in row(item) }
            }
        }
        .section(top: PaperSpace.xxl)
    }

    private func row(_ item: KitPickItem) -> some View {
        KitItemRow(item: item,
                   shortage: viewModel.shortage(for: item),
                   isWide: isWide,
                   toggle: { tick(item) },
                   count: { itemSheet = .count(item) },
                   notEnough: { itemSheet = .shortage(item) },
                   clearShortage: { clearingShortage = $0 })
    }

    private func tick(_ item: KitPickItem) {
        let ticking = !item.done
        viewModel.toggle(item)
        guard ticking else { lingering.remove(item.key); return }
        lingering.insert(item.key)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.25)) { _ = lingering.remove(item.key) }
        }
    }

    private func toPickList(_ items: [KitPickItem]) -> some View {
        ForEach(KitCategory.grouped(items), id: \.category) { group in
            VStack(alignment: .leading, spacing: 0) {
                PaperSectionHeader(KitCategory.title(group.category))
                if group.category == KitPickItem.unmappedCategory {
                    Notice(text: "The fittings library doesn't know these. They still go in the box.", tone: .soon)
                        .padding(.vertical, PaperSpace.s)
                }
                ForEach(group.items) { item in row(item) }
            }
            .section(top: PaperSpace.xxl)
        }
    }

    private func readOnlyList(_ kit: FittingKit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(kit.result.groups, id: \.category) { group in
                VStack(alignment: .leading, spacing: 0) {
                    PaperSectionHeader(KitCategory.title(group.category))
                    ForEach(group.items, id: \.id) { item in
                        FactRow(label: item.label, value: PaperFormat.int(item.qty))
                    }
                }
                .section(top: PaperSpace.xxl)
            }
            if !kit.result.unmapped.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    PaperSectionHeader(KitCategory.title(KitPickItem.unmappedCategory))
                    Notice(text: "The fittings library doesn't know these. They still go in the box.", tone: .soon)
                        .padding(.vertical, PaperSpace.s)
                    ForEach(kit.result.unmapped, id: \.name) { item in
                        FactRow(label: item.name, value: PaperFormat.int(item.qty))
                    }
                }
                .section(top: PaperSpace.xxl)
            }
        }
    }

    // MARK: - Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Photos") {
                if !viewModel.photos.isEmpty {
                    Text(PaperFormat.int(viewModel.photos.count)).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.tertiary)
                }
            }
            if let problem = viewModel.photoProblem {
                Notice(text: problem, tone: .soon).padding(.top, PaperSpace.s)
            }
            if !viewModel.photos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: PaperSpace.s)], spacing: PaperSpace.s) {
                    ForEach(viewModel.photos) { photo in
                        Button {
                            viewingPhoto = photo
                        } label: {
                            KitPhotoImage(jobId: jobId, photo: photo)
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Photo taken by \(photo.takenBy)")
                    }
                }
                .padding(.top, PaperSpace.m)
            }
            HStack(spacing: PaperSpace.m) {
                if cameraAvailable {
                    Button("Take a photo") { showingCamera = true }
                        .buttonStyle(.paperPill(.outline, .regular, fullWidth: true))
                }
                Button("Choose a photo") { showingLibrary = true }
                    .buttonStyle(.paperPill(.outline, .regular, fullWidth: true))
            }
            .disabled(viewModel.isUploading)
            .padding(.top, PaperSpace.m)

            if viewModel.isUploading {
                LoadingLine("Sending the photo").padding(.top, PaperSpace.m)
            }
        }
    }

    // MARK: - Finishing

    @ViewBuilder
    private func stepSection(_ picking: KitPicking?) -> some View {
        if let step = viewModel.kitStep {
            VStack(alignment: .leading, spacing: PaperSpace.m) {
                PaperSectionHeader(FittingKitViewModel.stepName) {
                    StatusText(step.displayState, tone: step.tone)
                }
                if step.isComplete {
                    Text("This kit has been finished.").paperType(.subhead).foregroundStyle(PaperColor.secondary)
                } else {
                    stepButtons(step, picking: picking)
                }
            }
        } else if viewModel.detail != nil {
            Text("This job has no \(FittingKitViewModel.stepName) step in ShopVOX, so the kit can't be finished from here.")
                .paperType(.footnote)
                .foregroundStyle(PaperColor.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Finish is in the bar along the bottom. The step starts with the first
    /// tick; Start is here for a kit opened without ticking, Pause for a break.
    @ViewBuilder
    private func stepButtons(_ step: JobStep, picking: KitPicking?) -> some View {
        let canStart = step.isActionable && step.action(.start)?.allowed == true
        let canPause = step.isActionable && step.action(.stop)?.allowed == true

        if step.isActive {
            Text("Started with the first tick. Pause it for a break or when the kit is left half-done.")
                .paperType(.footnote).foregroundStyle(PaperColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if canStart {
            Text("Ticking the first item starts it.")
                .paperType(.footnote).foregroundStyle(PaperColor.secondary)
        }

        if canStart || canPause {
            HStack(spacing: PaperSpace.m) {
                if canStart {
                    Button(step.isHalted ? "Resume" : "Start") { Task { await viewModel.perform(.start) } }
                        .buttonStyle(.paperPill(.outline, .regular, fullWidth: true))
                }
                if canPause {
                    Button("Pause") { Task { await viewModel.perform(.stop) } }
                        .buttonStyle(.paperPill(.outline, .regular, fullWidth: true))
                }
            }
            .disabled(viewModel.isMovingStep)
        }

        if !(step.isActionable && step.action(.complete)?.allowed == true), let reason = step.action(.complete)?.reason {
            Text(reason).paperType(.footnote).foregroundStyle(PaperColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - A line on the list

/// Which item sheet is up. Changing it while one is showing replaces it.
private enum KitItemSheet: Identifiable {
    case count(KitPickItem)
    case shortage(KitPickItem)

    var id: String {
        switch self {
        case .count(let item): "count:\(item.key)"
        case .shortage(let item): "shortage:\(item.key)"
        }
    }
}

private struct KitItemRow: View {
    let item: KitPickItem
    let shortage: KitShortage?
    /// An iPad: bigger type, read from arm's length at the bench.
    let isWide: Bool
    let toggle: () -> Void
    let count: () -> Void
    let notEnough: () -> Void
    let clearShortage: (KitShortage) -> Void

    private var checkState: PaperCheck.State {
        if item.done { return .done }
        return item.picked > 0 ? .active : .open
    }

    /// Once it's all picked the shortage has closed, or will when the tick lands.
    private var openShortage: KitShortage? { item.done ? nil : shortage }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainLine
            if let openShortage {
                shortageLine(openShortage)
                    // Lined up with the label, past the check and the count.
                    .padding(.leading, (isWide ? 34 + 60 : 30 + 48) + PaperSpace.m * 2)
                    .padding(.bottom, PaperSpace.s)
            }
        }
        .padding(.vertical, PaperSpace.xs)
        .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
        // The same choices on a long press anywhere on the row.
        .contextMenu { itemMenu }
    }

    /// What's under the ⋯: a part count, and the shelf being short.
    @ViewBuilder
    private var itemMenu: some View {
        Button("Count some", action: count)
        Button(openShortage == nil ? "Not enough on the shelf" : "Change shortage", action: notEnough)
        if let openShortage {
            Button("Clear shortage", role: .destructive) { clearShortage(openShortage) }
        }
    }

    /// How many first, since that's what the picker counts out; then what.
    private var mainLine: some View {
        HStack(spacing: PaperSpace.m) {
            Button(action: toggle) {
                HStack(spacing: PaperSpace.m) {
                    PaperCheck(checkState, size: isWide ? 34 : 30)
                    Text("\(PaperFormat.int(item.required))×")
                        .paperType(isWide ? .title : .headline, numeric: true)
                        .foregroundStyle(item.done ? PaperColor.secondary : PaperColor.ink)
                        .frame(minWidth: isWide ? 60 : 48, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label)
                            .paperType(isWide ? .bodyL : .body)
                            .foregroundStyle(item.done ? PaperColor.secondary : PaperColor.ink)
                            .strikethrough(item.done, color: PaperColor.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        if item.over {
                            StatusText("\(PaperFormat.int(item.picked - item.required)) too many: the kit may have changed", tone: .soon, lineLimit: nil)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: isWide ? 68 : 60)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.required) × \(item.label)")
            .accessibilityValue("\(item.picked) of \(item.required) picked")
            .accessibilityAddTraits(item.done ? .isSelected : [])

            // ⋯ for the rest: counting some, or saying the shelf is short. A
            // part-picked item shows its count there instead, so it stands out.
            Menu {
                itemMenu
            } label: {
                Group {
                    if item.picked > 0, !item.done {
                        Text("\(PaperFormat.int(item.picked)) of \(PaperFormat.int(item.required))")
                            .paperType(.subhead, numeric: true)
                            .foregroundStyle(PaperColor.ink)
                            .padding(.horizontal, PaperSpace.m)
                            .overlay(Capsule().strokeBorder(PaperColor.border, lineWidth: 1).frame(height: 36))
                    } else {
                        PaperIcon(.more, size: 18, color: PaperColor.secondary)
                    }
                }
                .frame(minWidth: 52, minHeight: 44)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("More for \(item.label)")
            .accessibilityValue(item.picked > 0 && !item.done ? "\(item.picked) of \(item.required) picked" : "")
        }
    }

    /// "Waiting on 4 more: reported by kit-ipad, Thu 16 Oct 11:30"
    private func shortageLine(_ shortage: KitShortage) -> some View {
        let when = DateFormatters.parseISO8601(shortage.reportedAt).map { Format.when($0) }
        let reported = ["reported by \(shortage.reportedBy)", when].compactMap { $0 }.joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 2) {
            StatusText("Waiting on \(PaperFormat.int(shortage.short)) more: \(reported)", tone: .held, lineLimit: nil)
            if let note = shortage.note, !note.isEmpty {
                Text(note)
                    .paperType(.footnote)
                    .foregroundStyle(PaperColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: PaperSpace.s) {
                Button("Change", action: notEnough)
                    .buttonStyle(.paperPill(.outline, .compact))
                Button("Clear") { clearShortage(shortage) }
                    .buttonStyle(.paperPill(.outline, .compact))
            }
            .padding(.top, PaperSpace.xs)
        }
    }
}

enum KitCategory {
    /// Grouped in the order the server lists them; unknown fittings come last.
    static func grouped(_ items: [KitPickItem]) -> [(category: String, items: [KitPickItem])] {
        var groups: [(category: String, items: [KitPickItem])] = []
        for item in items {
            if let i = groups.firstIndex(where: { $0.category == item.category }) {
                groups[i].items.append(item)
            } else {
                groups.append((item.category, [item]))
            }
        }
        return groups
    }

    static func title(_ category: String) -> String {
        category == KitPickItem.unmappedCategory ? "Not in the fittings library" : category.capitalized
    }
}

// MARK: - A partial count

private struct KitCountSheet: View {
    let item: KitPickItem
    let onSet: (Int) -> Void
    let onNotEnough: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(item: KitPickItem, onSet: @escaping (Int) -> Void, onNotEnough: @escaping () -> Void) {
        self.item = item
        self.onSet = onSet
        self.onNotEnough = onNotEnough
        // Empty rather than "0", so typing 3 doesn't read "03".
        _text = State(initialValue: item.picked > 0 ? String(item.picked) : "")
    }

    private var value: Int? { Int(text.trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        SheetScreen(item.label) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: PaperSpace.l) {
                Text("How many have been picked? The kit needs \(PaperFormat.int(item.required)).")
                    .paperType(.subhead, numeric: true)
                    .foregroundStyle(PaperColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                PaperHeroField(text: $text, unit: "picked", accessibilityLabel: "Number picked")
                    .keyboardType(.numberPad)
                    .onChange(of: text) { _, new in
                        let digits = new.filter(\.isNumber)
                        if digits != new { text = digits }
                    }

                Button("Set count") {
                    if let value { onSet(value) }
                    dismiss()
                }
                .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
                .disabled(value == nil)

                HStack(spacing: PaperSpace.m) {
                    Button("Pick all \(PaperFormat.int(item.required))") {
                        onSet(item.required)
                        dismiss()
                    }
                    .buttonStyle(.paperPill(.outline, .regular, fullWidth: true))
                    Button("Clear") {
                        onSet(0)
                        dismiss()
                    }
                    .buttonStyle(.paperPill(.outline, .regular, fullWidth: true))
                }

                // Running out while counting is the moment to say so. Swaps
                // this sheet for the shortage one, so no dismiss here.
                Button("Not enough on the shelf", action: onNotEnough)
                    .buttonStyle(.paperPill(.outline, .regular, fullWidth: true))
            }
            .padding(.top, PaperSpace.m)
        }
    }
}

// MARK: - Not enough on the shelf

private struct KitShortageSheet: View {
    let item: KitPickItem
    let existing: KitShortage?
    /// Nil once the server has it; otherwise the sentence to show.
    let onReport: (Int, String?) async -> String?

    private static let noteLimit = 500

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var note: String
    @State private var isSending = false
    @State private var problem: String?

    init(item: KitPickItem, existing: KitShortage?, onReport: @escaping (Int, String?) async -> String?) {
        self.item = item
        self.existing = existing
        self.onReport = onReport
        _text = State(initialValue: String(existing?.short ?? max(1, item.required - item.picked)))
        _note = State(initialValue: existing?.note ?? "")
    }

    private var value: Int? {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)), n >= 1 else { return nil }
        return n
    }

    private var reportedLine: String? {
        guard let existing else { return nil }
        let when = DateFormatters.parseISO8601(existing.reportedAt).map { Format.when($0) }
        let by = ["Reported by \(existing.reportedBy)", when].compactMap { $0 }.joined(separator: ", ")
        return "\(by). Sending again updates it."
    }

    var body: some View {
        SheetScreen(item.label) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: PaperSpace.l) {
                Text("How many more are needed? The kit needs \(PaperFormat.int(item.required)) and \(PaperFormat.int(item.picked)) have been picked.")
                    .paperType(.subhead, numeric: true)
                    .foregroundStyle(PaperColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let reportedLine {
                    StatusText(reportedLine, tone: .held, lineLimit: nil)
                }

                PaperHeroField(text: $text, unit: "more", accessibilityLabel: "Number more needed")
                    .keyboardType(.numberPad)
                    .onChange(of: text) { _, new in
                        let digits = new.filter(\.isNumber)
                        if digits != new { text = digits }
                    }

                VStack(alignment: .leading, spacing: PaperSpace.xs) {
                    PaperLabel("Note (optional)")
                    TextField("e.g. only 2 in the box", text: $note, axis: .vertical)
                        .paperType(.body)
                        .foregroundStyle(PaperColor.ink)
                        .lineLimit(2...5)
                        .padding(.bottom, PaperSpace.xs)
                        .overlay(alignment: .bottom) { Rectangle().fill(PaperColor.dot).frame(height: 1) }
                        .accessibilityLabel("Note")
                        .onChange(of: note) { _, new in
                            if new.count > Self.noteLimit { note = String(new.prefix(Self.noteLimit)) }
                        }
                }

                if let problem {
                    Notice(text: problem, tone: .held)
                }

                Button {
                    send()
                } label: {
                    if isSending {
                        ProgressView().tint(PaperColor.onAccent)
                    } else {
                        Text(existing == nil ? "Report shortage" : "Update shortage")
                    }
                }
                .buttonStyle(.paperPill(.accent, .floor, fullWidth: true))
                .disabled(value == nil || isSending)

                Text("It shows on Cabinet Lab so it gets ordered, and here for the next picker. It clears itself when the item is ticked as fully picked.")
                    .paperType(.footnote)
                    .foregroundStyle(PaperColor.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, PaperSpace.m)
        }
    }

    private func send() {
        guard let value, !isSending else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true
        problem = nil
        Task {
            if let failed = await onReport(value, trimmed.isEmpty ? nil : trimmed) {
                problem = failed
                isSending = false
            } else {
                dismiss()
            }
        }
    }
}

// MARK: - Photos

/// Fetched with the device's token, since photos have no public link. Kept in
/// memory for the session so the grid doesn't refetch each time it's drawn.
@MainActor
private enum KitPhotoCache {
    static let images = NSCache<NSString, UIImage>()
    static let service = JobIndexService()
}

private struct KitPhotoImage: View {
    let jobId: String
    let photo: KitPhoto
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            PaperColor.segment
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if failed {
                PaperIcon(.alert, size: 18, color: PaperColor.tertiary)
            } else {
                ProgressView().tint(PaperColor.secondary)
            }
        }
        .task(id: photo.id) {
            if let cached = KitPhotoCache.images.object(forKey: photo.id as NSString) {
                image = cached
                return
            }
            do {
                let data = try await KitPhotoCache.service.kitPhotoData(jobId: jobId, photoId: photo.id)
                guard let loaded = UIImage(data: data) else { throw JobIndexError.server(-1) }
                KitPhotoCache.images.setObject(loaded, forKey: photo.id as NSString)
                image = loaded
            } catch {
                failed = !Task.isCancelled
            }
        }
    }
}

private struct KitPhotoSheet: View {
    let jobId: String
    let photo: KitPhoto
    let jobName: String
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    private var takenLine: String {
        let when = DateFormatters.parseISO8601(photo.takenAt).map { Format.when($0) }
        return ["Taken by \(photo.takenBy)", when].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        SheetScreen("Kit photo") {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: PaperSpace.m) {
                KitPhotoImage(jobId: jobId, photo: photo, contentMode: .fit)
                    .frame(minHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(takenLine).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary)
                if let note = photo.note {
                    Text(note).paperType(.body).foregroundStyle(PaperColor.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Delete photo", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.paperText(PaperColor.danger, .subhead, weight: .medium))
            }
            .padding(.top, PaperSpace.m)
        }
        .confirmationDialog("Delete this photo of the kit for \(jobName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete photo", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// The system camera. Hands back the photo, or nil if it was cancelled.
private struct KitCameraView: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

// MARK: - On the job screen

/// One row under the job's proof: how far the kit has got, and the way to it.
struct FittingKitSection: View {
    let jobId: String
    var jobTitle: String?

    @ObservedObject private var queue = KitPickQueue.shared
    @State private var response: FittingKitResponse?
    @State private var problem: String?
    /// The server predates fitting kits, so there's nothing to offer.
    @State private var isUnavailable = false
    @State private var service = JobIndexService()

    var body: some View {
        Group {
            if !isUnavailable {
                VStack(alignment: .leading, spacing: 0) {
                    PaperSectionHeader("Fitting kit")
                    if let response, response.kit != nil {
                        NavigationLink {
                            FittingKitView(jobId: jobId, jobTitle: jobTitle)
                        } label: {
                            kitRow(response)
                        }
                        .buttonStyle(.plain)
                    } else if let need = response?.need, need.isNotNeeded {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(need.label).paperType(.body).foregroundStyle(PaperColor.ink)
                            Text(need.detail).paperType(.footnote).foregroundStyle(PaperColor.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, PaperSpace.m)
                    } else {
                        Text(emptyLine)
                            .paperType(.subhead)
                            .foregroundStyle(PaperColor.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, PaperSpace.m)
                    }
                }
            }
        }
        // Runs each time the screen comes back into view, which is what updates
        // the count after picking.
        .task { await load() }
    }

    /// "Pick the fitting kit", how far it's got, and what's short.
    private func kitRow(_ response: FittingKitResponse) -> some View {
        let picking = queue.displayed(jobId: jobId)
        return HStack(spacing: PaperSpace.m) {
            VStack(alignment: .leading, spacing: PaperSpace.xs) {
                Text(picking?.complete == true ? "Fitting kit picked" : "Pick the fitting kit")
                    .paperType(.body).foregroundStyle(PaperColor.ink)
                if let picking {
                    PaperBar(picking.counts.items > 0 ? Double(picking.counts.done) / Double(picking.counts.items) : 0,
                             color: picking.complete ? PaperColor.success : PaperColor.accent, height: 4)
                        .frame(height: 4)
                }
                Text(summary(response)).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary)
                ForEach((response.shortages ?? []).prefix(2)) { shortage in
                    StatusText("Waiting on \(PaperFormat.int(shortage.short)) × \(shortage.label ?? "an item")", tone: .held, lineLimit: 2)
                }
            }
            Spacer(minLength: PaperSpace.m)
            PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
        }
        .padding(.vertical, PaperSpace.m)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
    }

    private var emptyLine: String {
        if let problem { return problem }
        if let kitProblem = response?.kitProblem { return kitProblem }
        return response == nil ? "Loading the kit" : "No fittings list or ERP export has been added to this job yet."
    }

    private func summary(_ response: FittingKitResponse) -> String {
        guard let picking = queue.displayed(jobId: jobId) else {
            // The whole sentence is on the kit screen; a row has one line.
            return "Picking isn't available yet"
        }
        var parts = [picking.complete
            ? "All \(Format.count(picking.counts.items, "item")) picked"
            : "\(PaperFormat.int(picking.counts.done)) of \(Format.count(picking.counts.items, "item")) picked"]
        if let open = response.shortages, !open.isEmpty { parts.append("\(PaperFormat.int(open.count)) short") }
        if !response.photos.isEmpty { parts.append(Format.count(response.photos.count, "photo")) }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        let readAt = queue.revision(jobId: jobId)
        do {
            let fresh = try await service.fittingKit(jobId: jobId)
            response = fresh
            queue.adopt(fresh.picking, jobId: jobId, readAtRevision: readAt)
            problem = nil
        } catch JobIndexError.missingRoute {
            isUnavailable = true
        } catch {
            guard !Task.isCancelled else { return }
            problem = (error as? JobIndexError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#if DEBUG
/// The kit screen against MockKitStore, so the shortage line and sheet can be
/// seen without a server or a device token.
private struct MockFittingKitPreview: View {
    init() { Configuration.apiMode = .mock }

    var body: some View {
        NavigationStack {
            FittingKitView(jobId: "mock-job", jobTitle: "Sample customer")
        }
    }
}

#Preview("Fitting kit, with a shortage (mock)") {
    MockFittingKitPreview()
}
#endif
