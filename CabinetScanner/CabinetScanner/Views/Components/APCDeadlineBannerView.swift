import CabinetDesign
import SwiftUI

// MARK: - APC Deadline Banner
//
// Shown on Today and Packing when APC consignments are due today: an orange
// Notice (red once the cut-off is close or past) with an Open action that
// lists them.

struct APCDeadlineBannerView: View {
    @ObservedObject var viewModel: APCDeadlineViewModel
    @State private var showDetail = false

    var body: some View {
        if viewModel.shouldShow {
            Notice(
                text: viewModel.state.noticeText,
                tone: viewModel.state.tone,
                glyph: .truck,
                action: "Open",
                onAction: { showDetail = true }
            )
            .sheet(isPresented: $showDetail) {
                APCDeadlineDetailSheet(state: viewModel.state)
                    .paperSheet(detents: [.medium, .large])
            }
        }
    }
}

extension APCDeadlineState {
    /// Orange to act soon; red once there's half an hour or less, or it's gone.
    var tone: Tone {
        switch urgencyLevel {
        case .normal, .warning: .soon
        case .critical, .overdue: .held
        }
    }

    /// "1 h 20 min left", "Cut-off passed"
    var timeLeft: String {
        if isPastCutoff { return "Cut-off passed" }
        return "\(PaperFormat.duration(TimeInterval(minutesRemaining * 60))) left"
    }

    var noticeText: String {
        let what = "\(Format.count(count, "APC consignment")) due by the 14:00 cut-off"
        return isPastCutoff ? "\(what). The cut-off has passed." : "\(what) · \(timeLeft)"
    }
}

// MARK: - Detail Sheet

private struct APCDeadlineDetailSheet: View {
    let state: APCDeadlineState

    var body: some View {
        SheetScreen("APC cut-off") {
            VStack(alignment: .leading, spacing: 0) {
                if state.isEmpty {
                    PaperEmptyState("Nothing for APC today", message: "No APC consignments are due today.")
                } else {
                    Headline(value: "\(state.count)", unit: state.count == 1 ? "consignment due today" : "consignments due today",
                             style: .heroS)
                        .padding(.top, PaperSpace.l)
                    StatusText(state.isPastCutoff ? "The 14:00 cut-off has passed" : "14:00 cut-off · \(state.timeLeft)",
                               tone: state.tone, style: .subhead)
                        .padding(.top, PaperSpace.s)

                    VStack(alignment: .leading, spacing: 0) {
                        PaperSectionHeader("Due today")
                        ForEach(state.jobs) { job in
                            RowContainer {
                                HStack(alignment: .firstTextBaseline, spacing: PaperSpace.m) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(job.customer).paperType(.body).foregroundStyle(PaperColor.ink).lineLimit(1)
                                        Code("SO \(job.salesOrder)")
                                    }
                                    Spacer(minLength: PaperSpace.m)
                                    Text(job.shippingMethod).paperType(.footnote).foregroundStyle(PaperColor.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .section()
                }
            }
        }
    }
}
