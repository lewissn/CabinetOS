import CabinetDesign
import SwiftUI

// ============================================================
// MARK: - Today
// ============================================================
//
// What leaves today, read first. The figures are the dashboard's own
// dispatch query (jobs due today and tomorrow, by courier) and the week's
// packing from ReportingService; nothing here is estimated. There is no
// packed / packing / to-start bar because the dispatch query doesn't say
// which job is at which stage.

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @StateObject private var apcVM = APCDeadlineViewModel()
    @StateObject private var week = WeekFigures()
    @ObservedObject private var notifications = NotificationService.shared
    @StateObject private var search = JobSearchViewModel()
    @EnvironmentObject private var appState: AppState
    @State private var showingNotifications = false
    @State private var showingReports = false
    var switchToPackaging: () -> Void = {}

    /// Typing replaces the dashboard with results, exactly as it does on the
    /// Jobs tab. Looking a job up is the most common reason to pick the iPad
    /// up, and making somebody change tab first to do it was a step for
    /// nothing.
    private var isSearching: Bool { !search.trimmedQuery.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    PaperSearchField(text: $search.query, prompt: "Sales order, customer, Shopify number")
                        .padding(.top, PaperSpace.l)

                    if isSearching {
                        JobSearchResults(viewModel: search).padding(.top, PaperSpace.l)
                    } else {
                        dashboardContent
                    }
                }
                .screen()
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.immediately)
            .paperRootScreen()
            .navigationDestination(for: JobSearchResult.self) { result in
                JobDetailView(jobId: result.id, knownTitle: result.displayTitle, jobTitle: result.jobTitle, backLabel: "Today")
            }
            .refreshable {
                await vm.refresh()
                await apcVM.refresh()
                await notifications.refresh()
                await week.load(deviceId: appState.deviceId)
            }
            .task {
                await vm.refresh()
                await apcVM.refresh()
                apcVM.startCountdown()
                await notifications.refresh()
                await week.load(deviceId: appState.deviceId)
            }
            .sheet(isPresented: $showingNotifications) {
                NotificationsView().paperSheet()
            }
            .sheet(isPresented: $showingReports) {
                ReportingView().paperSheet()
            }
            .onDisappear {
                apcVM.stopCountdown()
            }
            .sheet(item: $vm.selectedTile) { detail in
                TileDetailSheet(detail: detail, sections: vm.sections(for: detail))
                    .paperSheet(detents: [.medium, .large])
            }
        }
    }

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
                // Not a sixth tab: the bar is already at five.
                NotificationBell { showingNotifications = true }
            }
            Text(greeting)
                .paperType(.greeting)
                .foregroundStyle(PaperColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("\(appState.stationId.prefix(1).uppercased() + appState.stationId.dropFirst()) station")
                .paperType(.footnote)
                .foregroundStyle(PaperColor.secondary)
        }
        .padding(.top, PaperSpace.s)
    }

    // MARK: Dashboard

    @ViewBuilder
    private var dashboardContent: some View {
        summary.section()

        if apcVM.shouldShow {
            APCDeadlineBannerView(viewModel: apcVM).section(top: PaperSpace.xxl)
        }

        // Above the couriers on purpose. A despatch date that has moved
        // changes what the numbers mean, so it has to be read first.
        DespatchNoticeBoard(showingAll: $showingNotifications).section()

        leaving.section()
        inHouseLoading
        thisWeek.section()
    }

    // MARK: Summary: the number that matters

    @ViewBuilder
    private var summary: some View {
        switch vm.state {
        case .loading where vm.intelligence.dueToday == 0 && vm.intelligence.dueTomorrow == 0:
            Headline(value: "–", unit: "jobs due out today", detail: "Loading")
        case .error(let message):
            PaperEmptyState("Today's despatch didn't load", message: message, actionTitle: "Try again") {
                Task { await vm.refresh() }
            }
        default:
            Button { vm.selectedTile = .dueToday } label: {
                Headline(
                    value: PaperFormat.int(vm.intelligence.dueToday),
                    unit: vm.intelligence.dueToday == 1 ? "job due out today" : "jobs due out today",
                    detail: "\(PaperFormat.int(vm.intelligence.dueTomorrow)) tomorrow"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the jobs due today")
        }
    }

    // MARK: Leaving, by courier

    @ViewBuilder
    private var leaving: some View {
        if vm.state == .loaded {
            VStack(alignment: .leading, spacing: 0) {
                PaperSectionHeader("By courier") {
                    Button("Packing", action: switchToPackaging)
                        .buttonStyle(.paperText(PaperColor.secondary, .footnote))
                }
                if vm.intelligence.courierGroups.isEmpty {
                    Text("Nothing is due out today or tomorrow.")
                        .paperType(.subhead)
                        .foregroundStyle(PaperColor.secondary)
                        .padding(.vertical, PaperSpace.m)
                } else {
                    ForEach(vm.intelligence.courierGroups) { group in
                        Button { vm.selectedTile = .courierGroup(group) } label: {
                            CourierGroupRow(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { vm.selectedTile = .dueTomorrow } label: {
                        PaperRow("Everything due tomorrow", trailing: PaperFormat.int(vm.intelligence.dueTomorrow), chevron: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: In-house loading order

    @ViewBuilder
    private var inHouseLoading: some View {
        if vm.state == .loaded && !vm.intelligence.inHouseJobs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                PaperSectionHeader("In-house van") {
                    Text("Load last drop first").paperType(.footnote).foregroundStyle(PaperColor.tertiary)
                }
                ForEach(Array(vm.intelligence.inHouseJobs.enumerated()), id: \.element.id) { index, job in
                    RowContainer {
                        HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                            Text("\(index + 1)")
                                .paperType(.subhead, numeric: true)
                                .foregroundStyle(PaperColor.secondary)
                                .frame(width: 22, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(job.customer).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(1)
                                Code("SO \(job.salesOrder)")
                            }
                            Spacer(minLength: PaperSpace.m)
                            if let postcode = job.postcode, !postcode.isEmpty {
                                Code(postcode, color: PaperColor.ink)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .section()
        }
    }

    // MARK: This week

    private var thisWeek: some View {
        VStack(alignment: .leading, spacing: PaperSpace.l) {
            PaperSectionHeader("Packing this week") {
                Button("Reports") { showingReports = true }
                    .buttonStyle(.paperText(PaperColor.secondary, .footnote))
            }
            if let summary = week.summary {
                HStack(alignment: .top) {
                    PaperStat(PaperFormat.int(summary.completionRates.totalBoxesPacked), label: "Boxes packed")
                    PaperStat(PaperFormat.int(summary.volume.totalItemsScanned), label: "Panels scanned")
                    let c = summary.completionRates
                    PaperStat(c.totalConsignments > 0
                              ? "\(PaperFormat.int(c.completedConsignments)) of \(PaperFormat.int(c.totalConsignments))"
                              : "0",
                              label: "Consignments done")
                }
            } else if let error = week.errorMessage {
                Text(error).paperType(.subhead).foregroundStyle(PaperColor.secondary)
            } else {
                HStack(alignment: .top) {
                    PaperStat("–", label: "Boxes packed")
                    PaperStat("–", label: "Panels scanned")
                    PaperStat("–", label: "Consignments done")
                }
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
// MARK: - Courier row
// ============================================================

private struct CourierGroupRow: View {
    let group: CourierGroup

    /// The one collection time the app knows: APC's 14:00 cut-off.
    private var isAPC: Bool { group.shippingMethod.localizedCaseInsensitiveContains("APC") }

    var body: some View {
        RowContainer {
            HStack(alignment: .center, spacing: PaperSpace.m) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.shippingMethod).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(2)
                    if isAPC {
                        Text("Cut-off 14:00").paperType(.footnote).foregroundStyle(PaperColor.secondary)
                    }
                }
                Spacer(minLength: PaperSpace.m)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(PaperFormat.int(group.dueToday)) today")
                        .paperType(.subhead, numeric: true)
                        .foregroundStyle(group.dueToday > 0 ? PaperColor.ink : PaperColor.secondary)
                    if group.dueTomorrow > 0 {
                        Text("\(PaperFormat.int(group.dueTomorrow)) tomorrow")
                            .paperType(.caption, numeric: true)
                            .foregroundStyle(PaperColor.tertiary)
                    }
                }
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
        }
    }

    var body: some View {
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
                                RowContainer {
                                    HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(job.customer).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(1)
                                            Code("SO \(job.salesOrder)")
                                        }
                                        Spacer(minLength: PaperSpace.m)
                                        if let postcode = job.postcode, !postcode.isEmpty {
                                            Code(postcode, color: PaperColor.ink)
                                        }
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .section(top: PaperSpace.xxl)
                    }
                }
            }
        }
    }
}
