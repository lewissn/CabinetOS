import SwiftUI

// MARK: - Production Board
//
// Yesterday / today / tomorrow / overdue / upcoming / recent, driven by order
// due dates.
//
// The caveat is not fine print here — it is rendered from the server's own
// response text, so this screen cannot drift into implying these are confirmed
// production schedules.

// MARK: - Production Board
//
// Yesterday / today / tomorrow / overdue / upcoming / recent, driven by order
// due dates. Shown in the Jobs tab whenever the search field is empty.
//
// The caveat is not fine print here — it is rendered from the server's own
// response text, so this screen cannot drift into implying these are confirmed
// production schedules.

struct ProductionBoard: View {
    @ObservedObject var viewModel: ProductionViewsViewModel

    var body: some View {
        VStack(spacing: 0) {
            viewPicker
            Divider()
            content
        }
    }

    // MARK: - Picker

    private var viewPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProductionDateView.allCases) { view in
                    Button {
                        viewModel.selectedView = view
                    } label: {
                        Label(view.title, systemImage: view.systemImage)
                            .font(.subheadline)
                            .fontWeight(viewModel.selectedView == view ? .semibold : .regular)
                            .padding(.horizontal, 14)
                            // Comfortably past the 44pt minimum: this is used
                            // one-handed, often wearing gloves.
                            .frame(minHeight: 44)
                            .background(
                                viewModel.selectedView == view
                                    ? Color.accentColor.opacity(0.15)
                                    : Color(.secondarySystemBackground),
                                in: Capsule()
                            )
                            .foregroundStyle(
                                viewModel.selectedView == view ? Color.accentColor : Color.primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.jobs.isEmpty {
            List(0..<6, id: \.self) { _ in ProductionRowSkeleton() }
                .listStyle(.plain)
                .allowsHitTesting(false)

        } else if let error = viewModel.errorMessage {
            ContentUnavailableView {
                Label("Could Not Load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent)
            }

        } else if viewModel.jobs.isEmpty {
            ContentUnavailableView {
                Label("Nothing Due", systemImage: viewModel.selectedView.systemImage)
            } description: {
                VStack(spacing: 8) {
                    Text(emptyMessage)
                    // An empty day is routine here, not a fault. Saying when
                    // the next orders are due makes it an answer rather than
                    // a dead end.
                    if let next = viewModel.response?.nextDue,
                       let date = JobDateFormatting.parse(next.date) {
                        Text("Next due \(JobDateFormatting.medium(date)) — \(next.count) order\(next.count == 1 ? "" : "s").")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

        } else {
            jobList
        }
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
        List {
            Section {
                ForEach(viewModel.jobs) { job in
                    NavigationLink(value: job) {
                        ProductionJobRow(job: job)
                    }
                }
            } header: {
                HStack {
                    Text("\(viewModel.jobs.count) order\(viewModel.jobs.count == 1 ? "" : "s")")
                    Spacer()
                    if let basis = viewModel.response?.dateBasisLabel {
                        Text(basis)
                            .foregroundStyle(.tertiary)
                    }
                }
            } footer: {
                // Straight from the server, so the honesty contract lives in
                // one place rather than being restated (and drifting) here.
                if let caveat = viewModel.response?.caveat {
                    Text(caveat)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await viewModel.load() }
    }
}

// MARK: - Row

struct ProductionJobRow: View {
    let job: ProductionJob

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let reference = job.primaryReference {
                    Text(reference)
                        .font(.subheadline.monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }

            if let step = job.currentStep {
                Label(step, systemImage: "gearshape.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                // No "order due" caption per row: the section header already
                // states the basis, and repeating it here crowded the date
                // into wrapping across two lines.
                DueDateLabel(
                    isoDate: job.orderDueDate,
                    isOverdue: job.isOverdue
                )

                if let method = job.shippingMethod {
                    Text(method)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        // Yields space before the date does.
                        .layoutPriority(-1)
                }

                Spacer(minLength: 4)

                ProvenanceBadge(
                    source: job.dataSource,
                    isStale: job.isStale,
                    compact: true
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Skeleton

struct ProductionRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 200, height: 15)
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 140, height: 11)
            RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 100, height: 11)
        }
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}
