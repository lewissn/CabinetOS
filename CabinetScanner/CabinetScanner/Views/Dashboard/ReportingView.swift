import CabinetDesign
import SwiftUI

// MARK: - Reports
//
// Opened as a sheet from Today. Packing figures for a period (today, this
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
        SheetScreen("Packing reports", onRefresh: { await vm.refresh() }) {
            VStack(alignment: .leading, spacing: 0) {
                PaperTextTabs(ReportingPeriod.allCases.map { ($0, $0.label) }, selection: $vm.selectedPeriod)
                    .padding(.top, PaperSpace.s)

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
        }
        .task {
            vm.deviceId = appState.deviceId
            await vm.refresh()
        }
    }

    // MARK: - Consignments finished: the headline

    private var completion: some View {
        let c = vm.summary.completionRates
        return VStack(alignment: .leading, spacing: PaperSpace.s) {
            PaperLabel("Consignments finished \(periodWord)")
            HStack(alignment: .firstTextBaseline, spacing: PaperSpace.s) {
                Text(PaperFormat.int(c.completedConsignments)).paperType(.hero, numeric: true).foregroundStyle(PaperColor.ink)
                if c.totalConsignments > 0 {
                    Text("of \(PaperFormat.int(c.totalConsignments))").paperType(.subhead, numeric: true).foregroundStyle(PaperColor.secondary)
                }
            }
            if c.totalConsignments > 0 {
                PaperBar(Double(c.completedConsignments) / Double(c.totalConsignments),
                         color: c.completedConsignments >= c.totalConsignments ? PaperColor.success : PaperColor.accent,
                         height: 4)
                    .padding(.top, PaperSpace.xs)
            }
            Text("\(Format.count(c.openConsignments, "still open", "still open"))")
                .paperType(.footnote, numeric: true)
                .foregroundStyle(PaperColor.secondary)
        }
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
