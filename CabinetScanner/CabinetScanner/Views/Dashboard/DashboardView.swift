import CabinetDesign
import SwiftUI

// ============================================================
// MARK: - Today
// ============================================================
//
// A dashboard that fits on one screen: the day that matters as a ring, three
// quiet figures, the week's rhythm and one line of news. The figures are the
// dispatch query (jobs due over the next five working days, with each job's
// ShopVOX step) and the week's packing from ReportingService; nothing here is
// estimated. Each figure opens the jobs behind it, grouped by courier.
//
// It only scrolls when it can't fit: a small phone or very large text.

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @StateObject private var week = WeekFigures()
    @ObservedObject private var notifications = NotificationService.shared
    @StateObject private var search = JobSearchViewModel()
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingNotifications = false
    @State private var showingVan = false
    /// Once the dispatch figures have loaded, a refresh keeps showing them
    /// rather than collapsing the page while it reloads.
    @State private var hasLoaded = false
    /// Drives the first draw: the ring sweeps round and the bars rise once
    /// there's something to show.
    @State private var revealed = false
    @State private var isRefreshing = false
    @State private var updatedAt: Date?
    /// Held explicitly so a scanned label replaces whatever is open rather
    /// than stacking on it, as on the Jobs tab.
    @State private var path = NavigationPath()
    @State private var scanningLabel = false
    var switchToPackaging: () -> Void = {}
    var switchToReports: () -> Void = {}

    /// Typing replaces the dashboard with results, exactly as it does on the
    /// Jobs tab. Looking a job up is the most common reason to pick the iPad
    /// up, and making somebody change tab first to do it was a step for
    /// nothing.
    private var isSearching: Bool { !search.trimmedQuery.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                // Fixed above both the dashboard and the results, so the field
                // keeps its focus as one replaces the other.
                VStack(alignment: .leading, spacing: 0) {
                    header
                    HStack(alignment: .center, spacing: PaperSpace.s) {
                        PaperSearchField(text: $search.query, prompt: "Order, customer, Shopify no.")
                        ScanLabelButton { scanningLabel = true }
                    }
                    .padding(.top, PaperSpace.l)
                }
                .screen()

                ZStack(alignment: .top) {
                    if isSearching {
                        ScrollView {
                            JobSearchResults(viewModel: search)
                                .padding(.top, PaperSpace.l)
                                .screen()
                                .padding(.bottom, 120)
                        }
                        .scrollDismissesKeyboard(.immediately)
                        .transition(.opacity.combined(with: .offset(y: 10)))
                    } else {
                        ViewThatFits(in: .vertical) {
                            dashboard.screen()
                            ScrollView { dashboard.screen() }
                                .refreshable { await refreshAll() }
                        }
                        // The keyboard rises over the dashboard rather than
                        // squeezing it into its scrolling form.
                        .ignoresSafeArea(.keyboard)
                        .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .animation(reduceMotion ? .easeInOut(duration: 0.15) : PaperMotion.spring, value: isSearching)
            }
            .paperRootScreen()
            .navigationDestination(for: JobSearchResult.self) { result in
                JobDetailView(jobId: result.id, knownTitle: result.displayTitle, jobTitle: result.jobTitle, backLabel: "Today")
            }
            .navigationDestination(for: LinkedJob.self) { linked in
                JobDetailView(jobId: linked.id, backLabel: "Today")
            }
            .navigationDestination(for: SalesOrderLookup.self) { lookup in
                JobLookupView(salesOrder: lookup.salesOrder, customer: "Sales order \(lookup.salesOrder)")
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
            .task { await refreshAll() }
            // Every tab is alive from launch: coming back to Today is when it
            // reloads, as is coming back to the app or a new day starting.
            .onTabReturn { await refreshAll() }
            .onResume { await refreshAll() }
            .onChange(of: vm.state) { _, state in
                if state == .loaded {
                    hasLoaded = true
                    revealed = true
                }
            }
            .sheet(isPresented: $showingNotifications) {
                NotificationsView().paperSheet()
            }
            .sheet(isPresented: $showingVan) {
                InHouseVanSheet(jobs: vm.intelligence.inHouseJobs)
                    .paperSheet(detents: [.medium, .large])
            }
            .sheet(item: $vm.selectedTile) { detail in
                TileDetailSheet(detail: detail, sections: vm.sections(for: detail))
                    .paperSheet(detents: [.medium, .large])
            }
        }
    }

    /// Open a scanned job label here on Today, so backing out returns to it.
    private func open(_ target: JobLabelTarget) {
        search.clear()
        path = NavigationPath()
        switch target {
        case .jobId(let id): path.append(LinkedJob(id: id))
        case .salesOrder(let number): path.append(SalesOrderLookup(salesOrder: number))
        }
    }

    private func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await vm.refresh()
        await notifications.refresh()
        await week.load(deviceId: appState.deviceId)
        if vm.state == .loaded { updatedAt = .now }
        isRefreshing = false
    }

    private var showsDispatch: Bool { vm.state == .loaded || (hasLoaded && vm.state == .loading) }

    // MARK: Header

    private var greeting: String {
        guard !appState.operatorName.isEmpty else { return vm.greeting }
        // "Good evening" → "Evening, Sam"
        let part = vm.greeting.replacingOccurrences(of: "Good ", with: "")
        return "\(part.prefix(1).uppercased() + part.dropFirst()), \(appState.operatorName)"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PaperSpace.xs) {
            HStack(alignment: .center) {
                Text(Format.today()).paperType(.subhead).foregroundStyle(PaperColor.secondary)
                Spacer()
                // The way through to the full list, carrying the unread count.
                NotificationBell { showingNotifications = true }
            }
            Text(greeting)
                .paperType(.greeting)
                .foregroundStyle(PaperColor.ink)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, PaperSpace.s)
    }

    // MARK: Dashboard

    private var focus: TodayFocus { TodayFocus(vm.intelligence) }

    /// Spacers with a floor and a ceiling: on a tall screen the blocks breathe,
    /// on a short one they close up before anything has to scroll.
    private func gap(_ minimum: CGFloat, _ maximum: CGFloat) -> some View {
        Spacer(minLength: minimum).frame(maxHeight: maximum * (isWide ? 1.6 : 1))
    }

    /// An iPad, where the same layout is drawn larger rather than left
    /// clustered at the top of a tall screen.
    private var isWide: Bool { sizeClass == .regular }

    private var dashboard: some View {
        let focus = focus
        return VStack(alignment: .leading, spacing: 0) {
            gap(PaperSpace.xxl, 56)

            if case .error(let message) = vm.state, !hasLoaded {
                PaperEmptyState("Today's despatch didn't load", message: message, actionTitle: "Try again") {
                    Task { await refreshAll() }
                }
            } else {
                FocusRing(focus: focus, isLoaded: showsDispatch, revealed: revealed, diameter: isWide ? 188 : 128) {
                    open(focus)
                }
            }

            gap(PaperSpace.xxl, 52)

            QuietFigures(
                intelligence: vm.intelligence,
                focus: focus,
                isLoaded: showsDispatch,
                boxesThisWeek: week.summary?.completionRates.totalBoxesPacked,
                onAPC: { vm.selectedTile = .courierGroup($0) },
                onOtherDay: { vm.selectedTile = focus.isToday ? .dueTomorrow : .dueToday },
                onWeek: switchToReports
            )

            gap(PaperSpace.xxl, 52)

            HStack(alignment: .firstTextBaseline) {
                Text("Next \(DashboardService.workingDaysShown) working days")
                    .paperType(.caption)
                    .foregroundStyle(PaperColor.tertiary)
                Spacer()
                if showsDispatch {
                    Text(Format.count(vm.intelligence.workingDays.reduce(0) { $0 + $1.total }, "job"))
                        .paperType(.caption, numeric: true)
                        .foregroundStyle(PaperColor.tertiary)
                        .contentTransition(.numericText())
                }
            }
            WeekRhythm(days: showsDispatch ? vm.intelligence.workingDays : [],
                       focusDate: focus.day?.date,
                       revealed: revealed,
                       barWidth: isWide ? 22 : 14) { vm.selectedTile = .day($0) }
                .frame(minHeight: 112, maxHeight: isWide ? 340 : 190)
                .padding(.top, PaperSpace.m)

            // Whatever height is left goes here, so the news and the footer
            // sit at the foot of the screen.
            Spacer(minLength: PaperSpace.m)

            TodayAlertLine { showingNotifications = true }

            footer
                .padding(.bottom, PaperSpace.m)
        }
    }

    /// The ring's day, opened as its jobs by courier.
    private func open(_ focus: TodayFocus) {
        guard let day = focus.day else { return }
        vm.selectedTile = focus.isToday ? .dueToday : (focus.isTomorrow ? .dueTomorrow : .day(day))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: PaperSpace.l) {
            Button {
                Task { await refreshAll() }
            } label: {
                HStack(spacing: 6) {
                    PaperIcon(.sync, size: 12, color: PaperColor.tertiary)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing && !reduceMotion
                                   ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                   : .default, value: isRefreshing)
                    Text(isRefreshing ? "Updating" : updatedAt.map { "Updated \(Format.time($0))" } ?? "Update")
                        .paperType(.caption, numeric: true)
                        .foregroundStyle(PaperColor.tertiary)
                }
                .frame(minHeight: PaperSpace.tap)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Update the dashboard")

            Spacer(minLength: 0)

            if showsDispatch && !vm.intelligence.inHouseJobs.isEmpty {
                Button("In-house van · \(vm.intelligence.inHouseJobs.count)") { showingVan = true }
                    .buttonStyle(.paperText(PaperColor.secondary, .caption))
            }
        }
    }
}

/// The week's packing figures for Today, from the same service and query as
/// Reports.
@MainActor
final class WeekFigures: ObservableObject {
    @Published private(set) var summary: ReportingSummary?
    @Published private(set) var errorMessage: String?
    private let service = ReportingService()

    func load(deviceId: String) async {
        do {
            summary = try await service.fetchReport(for: .thisWeek, deviceId: deviceId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// ============================================================
// MARK: - Stages
// ============================================================

extension DispatchStage {
    var label: String {
        switch self {
        case .toPack: "To pack"
        case .packing: "Packing"
        case .packed: "Packed"
        case .despatched: "Despatched"
        }
    }

    var tone: Tone {
        switch self {
        case .toPack: .neutral
        case .packing: .progress
        case .packed, .despatched: .done
        }
    }
}

private struct DispatchJobRow: View {
    let job: DispatchJob

    var body: some View {
        RowContainer {
            HStack(alignment: .center, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.customer).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(1)
                    HStack(spacing: PaperSpace.s) {
                        Code("SO \(job.salesOrder)")
                        if let postcode = job.postcode, !postcode.isEmpty { Code(postcode) }
                    }
                }
                Spacer(minLength: PaperSpace.m)
                StatusText(job.stage.label, tone: job.stage.tone)
                PaperIcon(.chevronRight, size: 14, color: PaperColor.faint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// ============================================================
// MARK: - Tile Detail Sheet
// ============================================================

private struct TileDetailSheet: View {
    let detail: TileDetail
    let sections: [DashboardViewModel.GroupedSection]

    private var totalJobs: Int {
        sections.reduce(0) { $0 + $1.jobs.count }
    }

    private var title: String {
        switch detail {
        case .dueToday: "Due today"
        case .dueTomorrow: "Due tomorrow"
        case .courierGroup(let g): g.shippingMethod
        case .day(let d): "Due \(Format.day(d.date))"
        }
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var content: some View {
        SheetScreen(title) {
            VStack(alignment: .leading, spacing: 0) {
                if sections.isEmpty {
                    PaperEmptyState("Nothing here", message: "There are no jobs for this.")
                } else {
                    Headline(value: PaperFormat.int(totalJobs), unit: totalJobs == 1 ? "job" : "jobs",
                             detail: Format.count(sections.count, "group"), style: .heroS)
                        .padding(.top, PaperSpace.l)
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            PaperSectionHeader(section.title) {
                                Text("\(section.jobs.count)").paperType(.footnote, numeric: true).foregroundStyle(PaperColor.tertiary)
                            }
                            ForEach(section.jobs) { job in
                                // Through to the job page, where a courier
                                // consignment can be raised for it.
                                NavigationLink {
                                    JobLookupView(salesOrder: job.salesOrder, customer: job.customer)
                                } label: {
                                    DispatchJobRow(job: job)
                                }
                                .buttonStyle(.plain)
                                .disabled(job.salesOrder == "—")
                            }
                        }
                        .section(top: PaperSpace.xxl)
                    }
                }
            }
        }
    }
}

// MARK: - Scan a job label

/// Sits beside the search field: the other way to find a job, by its label.
private struct ScanLabelButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PaperIcon(.qr, size: 22)
                .foregroundStyle(PaperColor.ink)
                .frame(width: 48, height: 48)
                .background(PaperColor.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(PaperColor.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scan a job label")
    }
}

// MARK: - In-house van

/// The in-house van's drops for today and tomorrow, in loading order: sorted
/// by postcode, so the last drop goes in first.
private struct InHouseVanSheet: View {
    let jobs: [DispatchJob]

    var body: some View {
        NavigationStack {
            SheetScreen("In-house van") {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Load last drop first")
                        .paperType(.footnote)
                        .foregroundStyle(PaperColor.tertiary)
                        .padding(.top, PaperSpace.s)
                    VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                        NavigationLink {
                            JobLookupView(salesOrder: job.salesOrder, customer: job.customer)
                        } label: {
                            RowContainer {
                                HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                                    Text("\(index + 1)")
                                        .paperType(.subhead, numeric: true)
                                        .foregroundStyle(PaperColor.secondary)
                                        .frame(width: 22, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(job.customer).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(1)
                                        HStack(spacing: PaperSpace.s) {
                                            Code("SO \(job.salesOrder)")
                                            if let postcode = job.postcode, !postcode.isEmpty { Code(postcode) }
                                        }
                                    }
                                    Spacer(minLength: PaperSpace.m)
                                    StatusText(job.stage.label, tone: job.stage.tone)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        .buttonStyle(.plain)
                        .disabled(job.salesOrder == "—")
                    }
                    }
                    .padding(.top, PaperSpace.l)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
