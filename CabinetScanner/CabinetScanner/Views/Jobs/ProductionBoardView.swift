import CabinetDesign
import SwiftUI

// MARK: - Production Board
//
// Overdue / this week / today / tomorrow / next week / upcoming / yesterday /
// recent, driven by order due dates. Shown in the Jobs tab whenever the
// search field is empty.
//
// The caveat is not fine print here — it is rendered from the server's own
// response text, so this screen cannot drift into implying these are confirmed
// production schedules.

struct ProductionBoard: View {
    @ObservedObject var viewModel: ProductionViewsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                PaperTextTabs(ProductionDateView.allCases.map { ($0, $0.label) }, selection: $viewModel.selectedView)
                    .padding(.trailing, PaperSpace.margin)
            }
            .scrollClipDisabled()

            content.padding(.top, PaperSpace.l)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.jobs.isEmpty {
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { _ in SearchResultSkeleton() }
            }
            .allowsHitTesting(false)

        } else if let error = viewModel.errorMessage {
            PaperEmptyState("The board didn't load", message: error, actionTitle: "Try again") {
                Task { await viewModel.load() }
            }

        } else if viewModel.jobs.isEmpty {
            // An empty day is routine here, not a fault. Saying when the next
            // orders are due makes it an answer rather than a dead end.
            PaperEmptyState("Nothing due", message: [emptyMessage, nextDueLine].compactMap { $0 }.joined(separator: " "))

        } else {
            jobList
        }
    }

    private var nextDueLine: String? {
        guard let next = viewModel.response?.nextDue, let date = JobDateFormatting.parse(next.date) else { return nil }
        return "Next due \(JobDateFormatting.medium(date)): \(Format.count(next.count, "order"))."
    }

    private var emptyMessage: String {
        switch viewModel.selectedView {
        case .overdue:           return "No orders are past their due date."
        case .thisWeek:          return "No orders are due this week."
        case .today:             return "No orders are due today."
        case .tomorrow:          return "No orders are due tomorrow."
        case .nextWeek:          return "No orders are due next week."
        case .upcoming:          return "No orders are due in the next four weeks."
        case .yesterday:         return "No orders were due yesterday."
        case .recentlyCompleted: return "No orders were due in the last two weeks."
        }
    }

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaperSectionHeader(Format.count(viewModel.jobs.count, "order")) {
                if let basis = viewModel.response?.dateBasisLabel {
                    Text(basis).paperType(.footnote).foregroundStyle(PaperColor.tertiary).lineLimit(1)
                }
            }
            ForEach(viewModel.jobs) { job in
                NavigationLink(value: job) {
                    ProductionJobRow(job: job)
                }
                .buttonStyle(.plain)
            }
            // Straight from the server, so the honesty contract lives in one
            // place rather than being restated (and drifting) here.
            if let caveat = viewModel.response?.caveat {
                Text(caveat)
                    .paperType(.footnote)
                    .foregroundStyle(PaperColor.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, PaperSpace.l)
            }
        }
    }
}

// MARK: - Row

struct ProductionJobRow: View {
    let job: ProductionJob

    private var detail: String? {
        let parts = [job.currentStep.map { "At \($0)" }, job.shippingMethod].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        JobRowContent(
            title: job.displayTitle,
            reference: job.primaryReference,
            subtitle: job.jobTitle.flatMap { $0 == job.displayTitle ? nil : $0 },
            due: DueLine.make(isoDate: job.orderDueDate, isOverdue: job.isOverdue),
            detail: detail,
            source: job.dataSource,
            isStale: job.isStale
        )
    }
}
