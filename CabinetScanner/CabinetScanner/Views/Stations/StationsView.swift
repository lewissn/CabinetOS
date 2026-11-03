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

    private var current: Station? { viewModel.stations.first { $0.id == currentId } }

    /// Polled only while somebody can see it.
    private var isWatching: Bool {
        isTabActive && scenePhase == .active && path.isEmpty && current != nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenTitle(current?.label ?? "Stations") {
                        BarIcon(glyph: .qr, label: "Scan a job label") { scanningLabel = true }
                    }
                    content
                }
                .screen()
                .padding(.bottom, 120)
            }
            .refreshable { await refresh() }
            .paperRootScreen()
            .navigationDestination(for: LinkedJob.self) { linked in
                JobDetailView(jobId: linked.id, knownTitle: linked.title, backLabel: current?.label ?? "Stations")
            }
            .navigationDestination(for: SalesOrderLookup.self) { lookup in
                JobLookupView(salesOrder: lookup.salesOrder, customer: "Sales order \(lookup.salesOrder)")
            }
            .navigationDestination(for: KitLink.self) { link in
                FittingKitView(jobId: link.jobId, jobTitle: link.title, backLabel: current?.label ?? "Stations")
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
            path.append(KitLink(jobId: job.jobId, title: job.customer))
        } else {
            path.append(LinkedJob(id: job.jobId, title: job.customer))
        }
    }

    private func open(_ target: JobLabelTarget) {
        path = NavigationPath()
        switch target {
        case .jobId(let id):
            if current?.isKit == true {
                path.append(KitLink(jobId: id, title: nil))
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

/// A job's picking list on a navigation stack.
struct KitLink: Hashable {
    let jobId: String
    let title: String?
}
