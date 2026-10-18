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
    /// Shipping method to show, or nil for all. Kept per device.
    @AppStorage("board.shippingFilter") private var shippingFilter = ""

    /// The shipping methods in this view, most jobs first.
    private var methods: [(name: String, count: Int)] {
        Dictionary(grouping: viewModel.jobs, by: { $0.shippingLabel })
            .map { ($0.key, $0.value.count) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
    }

    private var shownJobs: [ProductionJob] {
        guard !shippingFilter.isEmpty, methods.contains(where: { $0.name == shippingFilter }) else { return viewModel.jobs }
        return viewModel.jobs.filter { $0.shippingLabel == shippingFilter }
    }

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
            if methods.count > 1 {
                shippingChips.padding(.bottom, PaperSpace.l)
            }
            PaperSectionHeader(Format.count(shownJobs.count, "order")) {
                if let basis = viewModel.response?.dateBasisLabel {
                    Text(basis).paperType(.footnote).foregroundStyle(PaperColor.tertiary).lineLimit(1)
                }
            }
            ForEach(shownJobs) { job in
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

// MARK: - Shipping filter

extension ProductionBoard {
    /// "All" and one chip per shipping method in this view, with its count.
    /// A method that isn't in the view just shows everything.
    fileprivate var shippingChips: some View {
        let active = methods.contains(where: { $0.name == shippingFilter }) ? shippingFilter : ""
        return VStack(alignment: .leading, spacing: PaperSpace.xs) {
            PaperLabel("Shipping")
            PaperFlowLayout(spacing: PaperSpace.s) {
                Button("All \(viewModel.jobs.count)") { shippingFilter = "" }
                    .buttonStyle(.paperChip(selected: active.isEmpty))
                ForEach(methods, id: \.name) { method in
                    Button("\(method.name) \(method.count)") {
                        shippingFilter = active == method.name ? "" : method.name
                    }
                    .buttonStyle(.paperChip(selected: active == method.name))
                    .accessibilityLabel("\(method.name), \(method.count) orders")
                }
            }
        }
    }
}

extension ProductionJob {
    /// The shipping method as shown and filtered on; jobs without one group
    /// under "Not set" rather than vanishing from the filter.
    var shippingLabel: String {
        let m = shippingMethod?.trimmingCharacters(in: .whitespaces) ?? ""
        return m.isEmpty ? "Not set" : m
    }
}

// MARK: - Row

struct ProductionJobRow: View {
    let job: ProductionJob

    var body: some View {
        JobRowContent(
            title: job.displayTitle,
            reference: job.primaryReference,
            subtitle: job.jobTitle.flatMap { $0 == job.displayTitle ? nil : $0 },
            // A despatched job says so, rather than showing its due date.
            due: job.isComplete == true
                ? ("Despatched", .done)
                : DueLine.make(isoDate: job.orderDueDate, isOverdue: job.isOverdue),
            detail: job.isComplete == true ? nil : job.currentStep.map { "At \($0)" },
            tag: job.shippingMethod,
            source: job.dataSource,
            isStale: job.isStale
        )
    }
}
