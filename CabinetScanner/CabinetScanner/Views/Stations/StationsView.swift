import CabinetDesign
import SwiftUI

// MARK: - Stations
//
// A department's queue: what's in progress there and what's ready. One tap
// starts, pauses or finishes the job's ShopVOX step, which also moves its card
// on the production board and times the work. The department is remembered per
// device, so a tablet at the CNC opens on the CNC.
//
// The Packing tab is the other kind of station (scanning and boxing) and stays
// as it is.

struct StationsView: View {
    @StateObject private var viewModel = StationQueueViewModel()
    @AppStorage("stations.current") private var currentId = ""
    @Environment(\.isTabActive) private var isTabActive
    @Environment(\.scenePhase) private var scenePhase
    @State private var path = NavigationPath()
    @State private var scanningLabel = false
    /// The screen's width, which decides whether the kit station shows its
    /// queue and the open kit side by side.
    @State private var width: CGFloat = 0
    /// The kit open beside the queue, on a wide screen.
    @State private var openKit: KitLink?

    private var current: Station? { viewModel.stations.first { $0.id == currentId } }

    /// An iPad in landscape (or a wide window): the queue on the left, the
    /// kit being picked on the right. A phone, or an iPad in portrait, goes
    /// one screen at a time.
    private var isSplit: Bool { current?.isKit == true && width >= 900 }

    /// Polled only while somebody can see it.
    private var isWatching: Bool {
        isTabActive && scenePhase == .active && path.isEmpty && current != nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isSplit {
                    split
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            titleBar
                            content
                        }
                        .screen()
                        .padding(.bottom, 120)
                    }
                    .refreshable { await refresh() }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .paperRootScreen()
            .navigationDestination(for: LinkedJob.self) { linked in
                JobDetailView(jobId: linked.id, knownTitle: linked.title, backLabel: current?.label ?? "Stations")
            }
            .navigationDestination(for: SalesOrderLookup.self) { lookup in
                JobLookupView(salesOrder: lookup.salesOrder, customer: "Sales order \(lookup.salesOrder)")
            }
            .navigationDestination(for: KitLink.self) { link in
                FittingKitView(link: link, backLabel: current?.label ?? "Stations",
                               next: nextKit(after: link.jobId).map { next in
                                   KitNext(name: next.title ?? "the next kit") {
                                       path.removeLast(path.count)
                                       path.append(next)
                                   }
                               },
                               onFinished: { Task { await viewModel.loadQueue(stationId: currentId) } })
            }
            .fullScreenCover(isPresented: $scanningLabel) {
                JobLabelScannerView(
                    onFound: { target in
                        scanningLabel = false
                        open(target)
                    },
                    onCancel: { scanningLabel = false }
                )
            }
            .safeAreaInset(edge: .bottom) {
                if let outcome = viewModel.outcome {
                    StepActionBanner(result: outcome) { viewModel.outcome = nil }
                }
            }
        }
        // Side by side, a kit is always open: the most pressing one to start with.
        .onChange(of: viewModel.queue?.station.id, initial: true) { _, _ in chooseKitIfNeeded() }
        .onChange(of: isSplit) { _, split in
            if split { chooseKitIfNeeded() } else { openKit = nil }
        }
        .task(id: isTabActive) {
            if isTabActive, viewModel.stations.isEmpty { await viewModel.loadStations() }
        }
        .task(id: "\(currentId)|\(isWatching)") {
            guard isWatching else { return }
            while !Task.isCancelled {
                await viewModel.loadQueue(stationId: currentId)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private var titleBar: some View {
        ScreenTitle(current?.label ?? "Stations") {
            BarIcon(glyph: .qr, label: "Scan a job label") { scanningLabel = true }
        }
    }

    // MARK: - Side by side (fitting kits on a wide screen)

    private var split: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    titleBar
                    content
                }
                .paperMargins()
                .padding(.bottom, 120)
            }
            .refreshable { await refresh() }
            .frame(width: min(420, max(340, width * 0.36)))

            Rectangle().fill(PaperColor.hairlineSoft).frame(width: 1).ignoresSafeArea(edges: .vertical)

            Group {
                if let openKit {
                    FittingKitView(link: openKit, embedded: true,
                                   next: nextKit(after: openKit.jobId).map { next in
                                       KitNext(name: next.title ?? "the next kit") { self.openKit = next }
                                   },
                                   onFinished: { Task { await viewModel.loadQueue(stationId: currentId) } })
                        .id(openKit.jobId)
                } else {
                    PaperEmptyState("Choose a kit", message: "Its picking list opens here.")
                        .padding(PaperSpace.xxl)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// The kits worth opening next, in the order the queue shows them.
    private var pickableKits: [StationJob] {
        guard let queue = viewModel.queue, queue.station.isKit else { return [] }
        return KitQueuePlan.groups(queue).filter(\.isPickable).flatMap(\.jobs)
    }

    /// The next kit after this one that still needs picking.
    private func nextKit(after jobId: String) -> KitLink? {
        let kits = pickableKits
        let start = (kits.firstIndex { $0.jobId == jobId }).map { $0 + 1 } ?? 0
        let rest = kits[start...] + kits[..<min(start, kits.count)]
        return rest.first { $0.jobId != jobId && $0.progress?.complete != true }.map(KitLink.init)
    }

    private func chooseKitIfNeeded() {
        guard isSplit else { return }
        let kits = pickableKits
        if let openKit, viewModel.queue?.job(jobId: openKit.jobId) != nil || kits.isEmpty { return }
        openKit = kits.first.map(KitLink.init)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.stations.isEmpty {
            if let error = viewModel.stationsError {
                PaperEmptyState("The stations didn't load", message: error, actionTitle: "Try again") {
                    Task { await viewModel.loadStations() }
                }
                .section(top: PaperSpace.xxl)
            } else {
                LoadingLine("Loading the stations").section(top: PaperSpace.xxl)
            }
        } else if let current {
            VStack(alignment: .leading, spacing: 0) {
                stationPicker.padding(.top, PaperSpace.m)
                Text(current.hint)
                    .paperType(.subhead)
                    .foregroundStyle(PaperColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PaperSpace.m)
                queue(for: current)
            }
        } else {
            chooseStation
        }
    }

    /// First time here on this device: which department is it at?
    private var chooseStation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose the department this device works at. It opens here from then on, and you can change it at any time.")
                .paperType(.subhead)
                .foregroundStyle(PaperColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, PaperSpace.s)
                .padding(.bottom, PaperSpace.l)
            ForEach(viewModel.stations) { station in
                Button {
                    currentId = station.id
                } label: {
                    HStack(spacing: PaperSpace.m) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(station.label).paperType(.body).foregroundStyle(PaperColor.ink)
                            Text(station.hint).paperType(.footnote).foregroundStyle(PaperColor.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: PaperSpace.m)
                        PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
                    }
                    .frame(minHeight: 60)
                    .padding(.vertical, PaperSpace.s)
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var stationPicker: some View {
        PaperFlowLayout(spacing: PaperSpace.s) {
            ForEach(viewModel.stations) { station in
                Button(station.label) { currentId = station.id }
                    .buttonStyle(.paperChip(selected: station.id == currentId))
            }
        }
    }

    @ViewBuilder
    private func queue(for station: Station) -> some View {
        if let queue = viewModel.queue, queue.station.id == station.id {
            VStack(alignment: .leading, spacing: 0) {
                // A poll that fails leaves the last good list up, and says so.
                if let error = viewModel.queueError {
                    Notice(text: "This list may be out of date. \(error)", tone: .soon).padding(.top, PaperSpace.l)
                }
                ForEach(queue.notes, id: \.self) { note in
                    Notice(text: note, tone: .soon).padding(.top, PaperSpace.l)
                }
                if queue.isEmpty {
                    PaperEmptyState("Nothing here right now",
                                    message: "No jobs are in progress or ready at \(station.label).")
                        .section(top: PaperSpace.xxl)
                } else if station.isKit {
                    KitQueueList(queue: queue, selectedJobId: isSplit ? openKit?.jobId : nil) { job in
                        openRow(job, station: station)
                    }
                } else {
                    jobs("In progress", queue.inProgress, station: station)
                    jobs("Ready", queue.ready, station: station)
                    jobs("Booked to cut, not ready in ShopVOX yet", queue.booked, station: station)
                }
            }
        } else if let error = viewModel.queueError {
            PaperEmptyState("\(station.label) didn't load", message: error, actionTitle: "Try again") {
                Task { await viewModel.loadQueue(stationId: station.id) }
            }
            .section(top: PaperSpace.xxl)
        } else {
            LoadingLine("Loading \(station.label)").section(top: PaperSpace.xxl)
        }
    }

    @ViewBuilder
    private func jobs(_ title: String, _ jobs: [StationJob], station: Station) -> some View {
        if !jobs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PaperSectionHeader(title) {
                    Text(PaperFormat.int(jobs.count)).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.tertiary)
                }
                ForEach(jobs) { job in
                    StationJobRow(
                        job: job,
                        finishesInKit: station.isKit,
                        isMoving: viewModel.moving == job.id,
                        isAnyMoving: viewModel.moving != nil,
                        open: { openRow(job, station: station) },
                        tap: { action in perform(action, on: job) }
                    )
                }
            }
            .section(top: PaperSpace.xxl)
        }
    }

    // MARK: - Actions

    private func perform(_ action: StepActionKind, on job: StationJob) {
        Task { await viewModel.perform(action, on: job, stationId: currentId) }
    }

    private func refresh() async {
        await viewModel.loadStations()
        if current != nil { await viewModel.loadQueue(stationId: currentId) }
    }

    /// The fitting kit station works from the picking list; the rest from the job.
    private func openRow(_ job: StationJob, station: Station) {
        if station.isKit {
            if isSplit { openKit = KitLink(job) } else { path.append(KitLink(job)) }
        } else {
            path.append(LinkedJob(id: job.jobId, title: job.customer))
        }
    }

    private func open(_ target: JobLabelTarget) {
        path = NavigationPath()
        switch target {
        case .jobId(let id):
            if current?.isKit == true {
                let link = viewModel.queue?.job(jobId: id).map(KitLink.init) ?? KitLink(jobId: id, title: nil)
                if isSplit { openKit = link } else { path.append(link) }
            } else {
                path.append(LinkedJob(id: id))
            }
        case .salesOrder(let number):
            // Already in this queue, so there's no need to search for it.
            if let current, let job = viewModel.queue?.job(salesOrder: number) {
                openRow(job, station: current)
            } else {
                path.append(SalesOrderLookup(salesOrder: number))
            }
        }
    }
}

// MARK: - A job at a station

private struct StationJobRow: View {
    let job: StationJob
    /// At the fitting kit station, finishing happens on the kit itself, where
    /// the picker is asked for a photo, so this row opens it instead.
    let finishesInKit: Bool
    let isMoving: Bool
    let isAnyMoving: Bool
    let open: () -> Void
    let tap: (StepActionKind) -> Void

    @State private var confirmingFinish = false

    /// A running job can pause or finish; any other can start or finish.
    private var actions: [StepActionKind] {
        let first: StepActionKind = job.isRunning ? .stop : .start
        return finishesInKit ? [first] : [first, .complete]
    }

    private var canMove: Bool { job.shopvoxStepId != nil }

    /// Why a button shown here is greyed out, said once.
    private var reasons: [String] {
        guard canMove else {
            return ["This step isn't linked to ShopVOX yet, so it can't be moved from here."]
        }
        var seen = Set<String>()
        return actions.compactMap { action in
            let availability = job.availability(action)
            guard !availability.allowed, let reason = availability.reason, seen.insert(reason).inserted else { return nil }
            return reason
        }
    }

    private func title(_ action: StepActionKind) -> String {
        switch action {
        case .start: job.isHalted ? "Resume" : "Start"
        case .stop: "Pause"
        case .complete: "Finish"
        }
    }

    private func isEnabled(_ action: StepActionKind) -> Bool {
        canMove && job.availability(action).allowed && !isAnyMoving
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaperSpace.m) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: PaperSpace.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                        Text(job.displayName).paperType(.bodyL).foregroundStyle(PaperColor.ink).lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: PaperSpace.s)
                        if let due = DueLine.make(isoDate: job.despatchDate) {
                            StatusText(due.text, tone: due.tone).fixedSize()
                        }
                        PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
                    }
                    HStack(spacing: PaperSpace.m) {
                        if let so = job.salesOrderNumber { Code("SO \(so)") }
                        if let shopify = job.shopifyOrderNumber { Code("#\(shopify)") }
                    }
                    if let facts {
                        Text(facts).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    if let status {
                        StatusText(status.text, tone: status.tone, lineLimit: nil).padding(.top, 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: PaperSpace.m) {
                ForEach(actions, id: \.self) { action in
                    let primary = action == actions.first && !job.isRunning || action == .complete && job.isRunning
                    Button {
                        // ShopVOX has no un-complete, so Finish asks first.
                        if action == .complete { confirmingFinish = true } else { tap(action) }
                    } label: {
                        if isMoving, primary {
                            ProgressView().tint(PaperColor.onAccent)
                        } else {
                            Text(title(action))
                        }
                    }
                    .buttonStyle(.paperPill(primary ? .accent : .outline, .floor, fullWidth: true))
                    .disabled(!isEnabled(action))
                    .accessibilityHint("\(job.stepName) for \(job.displayName)")
                }
                if finishesInKit {
                    Button("Open kit", action: open)
                        .buttonStyle(.paperPill(job.isRunning ? .accent : .outline, .floor, fullWidth: true))
                }
            }
            // On the row, so on an iPad it points at the job it's asking about.
            .confirmationDialog("Finish \(job.stepName) for \(job.displayName)?",
                                isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button("Finish \(job.stepName)") { tap(.complete) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(job.salesOrderNumber.map { "SO \($0). " } ?? "")This marks the step done in ShopVOX. It can't be undone from the app.")
            }

            ForEach(reasons, id: \.self) { reason in
                Text(reason).paperType(.footnote).foregroundStyle(PaperColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, PaperSpace.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { PaperHairline(color: PaperColor.hairlineSoft) }
    }

    /// "CNC - Manufacture · 14.2 m² · 32 parts · APC · Cutting Mon 9 Nov"
    private var facts: String? {
        var parts = [job.stepName]
        if let area = job.areaM2 { parts.append("\(PaperFormat.trimmed(area)) m²") }
        if let count = job.parts { parts.append(Format.count(count, "part")) }
        if let carrier = job.carrier { parts.append(carrier) }
        if let day = job.cutDay.flatMap(JobDateFormatting.parse) { parts.append("Cutting \(JobDateFormatting.medium(day))") }
        return parts.joined(separator: " · ")
    }

    private var status: (text: String, tone: Tone)? {
        if job.isRunning {
            var line = "Running"
            if let started = job.startedAt.flatMap(DateFormatters.parseISO8601) { line += " since \(Format.when(started))" }
            if let who = job.startedByName { line += " · \(who)" }
            return (line, .progress)
        }
        return job.isHalted ? ("Paused", .progress) : nil
    }
}

/// A job's picking list on a navigation stack. What the queue already knows
/// about the job comes along, so the kit's header has it before the job loads.
struct KitLink: Hashable {
    let jobId: String
    let title: String?
    var salesOrder: String?
    var despatchDate: String?
    var carrier: String?

    init(jobId: String, title: String?) {
        self.jobId = jobId
        self.title = title
    }

    init(_ job: StationJob) {
        jobId = job.jobId
        title = job.customer
        salesOrder = job.salesOrderNumber
        despatchDate = job.despatchDate
        carrier = job.carrier
    }
}

/// "Next kit: R. Okafor", offered once a kit is finished.
struct KitNext {
    let name: String
    let open: () -> Void
}

// MARK: - The fitting kit queue
//
// Grouped by when the kit goes out, since that's what decides which one to
// pick next. Kits held up by a shortage sit apart, so a delivery shows which
// ones it frees up. Kits not reached yet and kits with nothing to pick come
// last and quieter. No Start or Pause here: the step starts with the first
// tick, and finishing happens on the kit, where the photo is asked for.

struct KitQueueGroup: Identifiable {
    enum Kind { case day, waitingOnStock, comingUp, nothingToPick }

    let id: String
    let title: String
    let kind: Kind
    let jobs: [StationJob]

    var isPickable: Bool { kind == .day || kind == .waitingOnStock }
}

enum KitQueuePlan {
    static func groups(_ queue: StationQueue, now: Date = .now) -> [KitQueueGroup] {
        let all = queue.inProgress + queue.ready
        let comingUp = all.filter(\.isPending)
        let waiting = all.filter { job in
            !job.isPending && !job.isRunning && !(job.progress?.shortages ?? []).isEmpty && job.progress?.complete != true
        }
        let rest = all.filter { job in !job.isPending && !waiting.contains(job) }

        // Running first within a day, then as the server sorts them.
        let order = Dictionary(rest.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        var days: [(key: String, title: String, jobs: [StationJob])] = []
        for job in rest {
            let (key, title) = day(job.despatchDate, now: now)
            if let i = days.firstIndex(where: { $0.key == key }) {
                days[i].jobs.append(job)
            } else {
                days.append((key, title, [job]))
            }
        }
        var groups = days.sorted { $0.key < $1.key }.map { day in
            KitQueueGroup(id: "day:\(day.key)", title: day.title, kind: .day,
                          jobs: day.jobs.sorted { a, b in
                              a.isRunning != b.isRunning ? a.isRunning : (order[a.id] ?? 0) < (order[b.id] ?? 0)
                          })
        }
        if !waiting.isEmpty { groups.append(KitQueueGroup(id: "stock", title: "Waiting on stock", kind: .waitingOnStock, jobs: waiting)) }
        if !comingUp.isEmpty { groups.append(KitQueueGroup(id: "coming", title: "Coming up", kind: .comingUp, jobs: comingUp)) }
        if let none = queue.noKit, !none.isEmpty {
            groups.append(KitQueueGroup(id: "none", title: "Nothing to pick", kind: .nothingToPick, jobs: none))
        }
        return groups
    }

    /// A sort key and a heading: "Late", "Going out today", "Tomorrow", "Going out Mon 9 Nov".
    private static func day(_ iso: String?, now: Date) -> (String, String) {
        guard let iso, let date = JobDateFormatting.parse(iso) else { return ("9", "No despatch date") }
        let cal = Calendar.london
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        if days < 0 { return ("0", "Late") }
        if days == 0 { return ("1", "Going out today") }
        if days == 1 { return ("2", "Going out tomorrow") }
        return ("3\(iso)", "Going out \(JobDateFormatting.medium(date))")
    }
}

struct KitQueueList: View {
    let queue: StationQueue
    /// The kit open beside the list, on a wide screen.
    let selectedJobId: String?
    let open: (StationJob) -> Void

    @State private var showingNothingToPick = false

    var body: some View {
        ForEach(KitQueuePlan.groups(queue)) { group in
            VStack(alignment: .leading, spacing: 0) {
                if group.kind == .nothingToPick {
                    nothingToPickHeader(group)
                    if showingNothingToPick {
                        Text(queue.noKitMode == "on"
                             ? "Their files show nothing to pick. The step completes by itself after Pack & Wrap."
                             : "Their files show nothing to pick. Check one before finishing it.")
                            .paperType(.footnote)
                            .foregroundStyle(PaperColor.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, PaperSpace.s)
                        rows(group)
                    }
                } else {
                    PaperSectionHeader(group.title) {
                        Text(PaperFormat.int(group.jobs.count)).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.tertiary)
                    }
                    rows(group)
                }
            }
            .section(top: PaperSpace.xxl)
        }
    }

    private func rows(_ group: KitQueueGroup) -> some View {
        ForEach(group.jobs) { job in
            KitQueueRow(job: job, kind: group.kind, isSelected: job.jobId == selectedJobId) { open(job) }
        }
    }

    private func nothingToPickHeader(_ group: KitQueueGroup) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { showingNothingToPick.toggle() }
        } label: {
            PaperSectionHeader("\(group.title) (\(PaperFormat.int(group.jobs.count)))") {
                PaperIcon(showingNothingToPick ? .chevronDown : .chevronRight, size: 12, color: PaperColor.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(showingNothingToPick ? "Hides them" : "Shows them")
    }
}

private struct KitQueueRow: View {
    let job: StationJob
    let kind: KitQueueGroup.Kind
    let isSelected: Bool
    let open: () -> Void

    @ObservedObject private var picks = KitPickQueue.shared

    /// Ticks made here show at once, before the next poll: on the kit that's
    /// open beside the list, or one with ticks still waiting to send. Otherwise
    /// the server's figure, which has other devices' ticks too.
    private var counts: (done: Int, items: Int, complete: Bool)? {
        if isSelected || picks.waitingCount(jobId: job.jobId) > 0, let local = picks.displayed(jobId: job.jobId) {
            return (local.counts.done, local.counts.items, local.complete)
        }
        return job.progress.map { ($0.done, $0.items, $0.complete) }
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: PaperSpace.xs) {
                HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                    Text(job.displayName).paperType(.bodyL).foregroundStyle(PaperColor.ink).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: PaperSpace.s)
                    // In a day's group the heading already says when.
                    if kind != .day, let due = DueLine.make(isoDate: job.despatchDate) {
                        StatusText(due.text, tone: due.tone).fixedSize()
                    } else if let counts, kind == .day {
                        Text("\(PaperFormat.int(counts.done)) / \(PaperFormat.int(counts.items))")
                            .paperType(.subhead, numeric: true)
                            .foregroundStyle(counts.complete ? PaperColor.success : PaperColor.secondary)
                            .fixedSize()
                    }
                    PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
                }
                if let refs { Text(refs).paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary) }
                if let counts, kind == .day || kind == .waitingOnStock {
                    PaperBar(counts.items > 0 ? Double(counts.done) / Double(counts.items) : 0,
                             color: counts.complete ? PaperColor.success : PaperColor.accent, height: 4)
                        .frame(height: 4)
                        .padding(.top, 2)
                }
                if let status { StatusText(status.text, tone: status.tone, lineLimit: nil).padding(.top, 2) }
                ForEach(shortLines, id: \.self) { line in
                    StatusText(line, tone: .held, lineLimit: 2)
                }
            }
            .padding(.vertical, PaperSpace.m)
            .padding(.horizontal, isSelected ? PaperSpace.s : 0)
            .background(isSelected ? PaperColor.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if !isSelected { PaperHairline(color: PaperColor.hairlineSoft) } }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "SO 12056 · #4410 · APC"
    private var refs: String? {
        let parts = [job.salesOrderNumber.map { "SO \($0)" }, job.shopifyOrderNumber.map { "#\($0)" }, job.carrier].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var status: (text: String, tone: Tone)? {
        switch kind {
        case .comingUp:
            return (job.nowAt.map { "Not at kits yet: now at \($0)" } ?? "Not at kits yet", .neutral)
        case .nothingToPick:
            return job.autoComplete.map { ($0.reason, $0.outcome == "held" ? Tone.soon : .neutral) }
                ?? job.kit.map { ($0.detail, .neutral) }
        case .day, .waitingOnStock:
            break
        }
        if job.isRunning {
            var line = "Picking"
            if let started = job.startedAt.flatMap(DateFormatters.parseISO8601) { line += " since \(Format.when(started))" }
            if let who = job.startedByName { line += " · \(who)" }
            return (line, .progress)
        }
        guard let counts else {
            // No kit list: say what the files show, if anything.
            if job.kit?.state == "check" { return (job.kit?.detail ?? "Check this job's fittings.", .soon) }
            return ("No fittings list yet", .neutral)
        }
        if counts.complete {
            let photographed = (job.progress?.photos ?? 0) > 0
            return photographed ? ("All picked · ready to finish", .done) : ("All picked · needs a photo", .soon)
        }
        if job.isHalted, counts.done > 0 { return ("Paused", .progress) }
        return nil
    }

    /// "Waiting on 4 × Drawer runner 500 mm (pair)", two at most.
    private var shortLines: [String] {
        guard kind == .day || kind == .waitingOnStock, let shorts = job.progress?.shortages, !shorts.isEmpty else { return [] }
        var lines = shorts.prefix(2).map { "Waiting on \(PaperFormat.int($0.short)) × \($0.label)" }
        if shorts.count > 2 { lines.append("and \(Format.count(shorts.count - 2, "more item"))") }
        return lines
    }
}
