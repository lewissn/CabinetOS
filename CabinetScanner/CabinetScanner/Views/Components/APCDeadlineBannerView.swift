import SwiftUI

// MARK: - APC Deadline Banner
//
// Reusable banner shown on Dashboard and Packaging tabs when APC
// consignments are due today. Tapping opens a detail sheet.

struct APCDeadlineBannerView: View {
    @ObservedObject var viewModel: APCDeadlineViewModel
    @State private var showDetail = false

    var body: some View {
        if viewModel.shouldShow {
            Button { showDetail = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(urgencyColor)
                        .symbolEffect(.pulse, options: .repeating,
                                      isActive: viewModel.state.urgencyLevel == .critical
                                             || viewModel.state.urgencyLevel == .overdue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("APC Deadline")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text("\(viewModel.state.count) consignment\(viewModel.state.count == 1 ? "" : "s") due")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(viewModel.state.timeRemainingText)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(urgencyColor)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay {
                            if viewModel.state.urgencyLevel == .critical
                                || viewModel.state.urgencyLevel == .overdue {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(.red.opacity(0.08))
                            }
                        }
                }
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showDetail) {
                APCDeadlineDetailSheet(state: viewModel.state)
            }
        }
    }

    // MARK: - Urgency styling

    private var urgencyColor: Color {
        switch viewModel.state.urgencyLevel {
        case .normal:   return .orange
        case .warning:  return .orange
        case .critical: return .red
        case .overdue:  return .red
        }
    }

}

// MARK: - Detail Sheet

private struct APCDeadlineDetailSheet: View {
    let state: APCDeadlineState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if state.isEmpty {
                    emptyContent
                } else {
                    jobList
                }
            }
            .navigationTitle("APC Deadline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var jobList: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("2pm Cutoff")
                            .font(.headline)
                        Text(state.timeRemainingText)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(countdownColor)
                    }
                    Spacer()
                    Text("\(state.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(countdownColor)
                }
                .padding(.vertical, 4)
            }

            Section("Consignments Due") {
                ForEach(state.jobs) { job in
                    APCJobRow(job: job)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("No APC jobs due today")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var countdownColor: Color {
        switch state.urgencyLevel {
        case .normal:   return .orange
        case .warning:  return .orange
        case .critical: return .red
        case .overdue:  return .red
        }
    }
}

// MARK: - Job Row

private struct APCJobRow: View {
    let job: APCDeadlineJob

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.customer)
                    .font(.body)
                    .fontWeight(.medium)

                Text("SO \(job.salesOrder)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text(job.shippingMethod)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1), in: Capsule())
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 2)
    }
}
