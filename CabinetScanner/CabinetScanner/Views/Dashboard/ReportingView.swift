import CabinetDesign
import SwiftUI

// MARK: - Reports
//
// Its own tab (it replaced Stock). Packing figures for a period (today, this
// week, this month) from ReportingService. The service returns totals for
// the period only, with no day-by-day series, so there are figures and
// stats here rather than charts. Wrapping is shown as plain numbers: no
// points, standings or streaks.

struct ReportingView: View {
    @StateObject private var vm = ReportingViewModel()
    @EnvironmentObject var appState: AppState
    @ObservedObject private var wrapStats = WrapStatsService.shared

    private var periodWord: String {
        switch vm.selectedPeriod {
        case .today: "today"
        case .thisWeek: "this week"
        case .thisMonth: "this month"
        case .allTime: "all time"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ScreenTitle("Reports")
                    PaperTextTabs(ReportingPeriod.allCases.map { ($0, $0.label) }, selection: $vm.selectedPeriod)
                        .padding(.top, PaperSpace.m)

                    if vm.isLoading {
                        LoadingLine("Loading the figures").section(top: PaperSpace.xxl)
                    } else if let error = vm.errorMessage {
                        PaperEmptyState("The figures didn't load", message: error, actionTitle: "Try again") {
                            Task { await vm.refresh() }
                        }
                        .section(top: PaperSpace.xxl)
                    } else {
                        completion.section(top: PaperSpace.xxl)
                        volume.section()
                        speed.section()
                        wrapping.section()
                    }
                }
                .screen()
                .padding(.bottom, 120)
            }
            .refreshable { await vm.refresh() }
            .paperRootScreen()
        }
        .task {
            vm.deviceId = appState.deviceId
            await vm.refresh()
        }
        // Every tab is alive from launch; coming back is when it refreshes.
        .onTabReturn { await vm.refreshIfStale() }
        .onResume { await vm.refreshIfStale() }
    }

    // MARK: - Consignments finished: the headline

    /// A centred ring, as on Today: the share of the period's consignments
    /// finished, with the count inside it.
    private var completion: some View {
        let c = vm.summary.completionRates
        let fraction = c.totalConsignments > 0 ? Double(c.completedConsignments) / Double(c.totalConsignments) : 0
        return VStack(spacing: PaperSpace.m) {
            ZStack {
                Circle().stroke(PaperColor.track, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0, min(1, fraction)))
                    .stroke(PaperColor.success, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 1.0, dampingFraction: 0.9), value: fraction)
                VStack(spacing: 2) {
                    Text("Finished \(periodWord)")
                        .paperType(.footnote)
                        .foregroundStyle(PaperColor.secondary)
                    Text(PaperFormat.int(c.completedConsignments))
                        .font(.brand(52, .light, relativeTo: .largeTitle))
                        .tracking(-1.6)
                        .monospacedDigit()
                        .foregroundStyle(PaperColor.ink)
                        .contentTransition(.numericText(value: Double(c.completedConsignments)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(c.totalConsignments > 0 ? "of \(PaperFormat.int(c.totalConsignments)) consignments" : "consignments")
                        .paperType(.caption, numeric: true)
                        .foregroundStyle(PaperColor.tertiary)
                }
                .padding(.horizontal, 20)
                .multilineTextAlignment(.center)
            }
            .frame(width: 176, height: 176)
            .padding(3)
            .animation(.snappy, value: c.completedConsignments)

            Text("\(Format.count(c.openConsignments, "still open", "still open"))")
                .paperType(.footnote, numeric: true)
                .foregroundStyle(PaperColor.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Volume

    private var volume: some View {
        let v = vm.summary.volume
        let c = vm.summary.completionRates
        return VStack(alignment: .leading, spacing: PaperSpace.l) {
            PaperSectionHeader("Packed")
            HStack(alignment: .top) {
                PaperStat(PaperFormat.int(v.totalBoxes), label: "Boxes")
                PaperStat(PaperFormat.int(v.totalItemsScanned), label: "Panels scanned")
                PaperStat(c.totalConsignments > 0 ? PaperFormat.trimmed((c.averageBoxesPerConsignment * 10).rounded() / 10) : "–",
                          label: "Boxes a consignment")
            }
        }
    }

    // MARK: - Speed

    private var speed: some View {
        let s = vm.summary.packingSpeed
        return VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Speed")
            PaperRow("Time to finish a consignment", detail: "Average, first scan to finished",
                     trailing: s.averageCompletionMinutes > 0 ? PaperFormat.duration(s.averageCompletionMinutes * 60) : "–")
            PaperRow("Panels a working day", detail: "Average \(periodWord)",
                     trailing: s.itemsScannedInPeriod > 0 ? PaperFormat.int(s.averageItemsPerDay) : "–")
        }
    }

    // MARK: - Wrapping, as plain numbers

    private var wrapping: some View {
        let w = vm.summary.wrapLeague
        return VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader("Wrapping")
            PaperRow("Boxes wrapped", detail: periodWord.prefix(1).uppercased() + periodWord.dropFirst(),
                     trailing: PaperFormat.int(w.wrappedBoxes))
            PaperRow("Wrapped without a fix", detail: "Not reopened by someone else",
                     trailing: w.wrappedBoxes > 0 ? "\(PaperFormat.int(w.cleanWrappedBoxes)) of \(PaperFormat.int(w.wrappedBoxes))" : "–")
            // Local to this phone and always available, even offline.
            PaperRow("Boxes from this device today", trailing: PaperFormat.int(wrapStats.boxesToday))
        }
    }
}

extension ReportingPeriod {
    var label: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This week"
        case .thisMonth: "This month"
        case .allTime: "All time"
        }
    }
}
