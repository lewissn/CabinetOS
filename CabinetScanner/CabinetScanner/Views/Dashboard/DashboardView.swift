import SwiftUI

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    statsRow
                    upcomingSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await vm.refresh() }
            .task { await vm.refresh() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.greeting)
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text(vm.formattedDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "shippingbox.fill")
                .font(.system(size: 28))
                .foregroundStyle(.blue)
        }
        .padding(.top, 16)
    }

    // MARK: - Stats cards

    private var statsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if vm.state == .loading {
                    ForEach(0..<3, id: \.self) { _ in
                        skeletonCard
                    }
                } else {
                    StatCard(
                        title: "Due Today",
                        value: vm.summary.dueToday,
                        subtitle: "Jobs",
                        accentColor: .blue
                    )
                    StatCard(
                        title: "Due Tomorrow",
                        value: vm.summary.dueTomorrow,
                        subtitle: "Jobs",
                        accentColor: .orange
                    )
                    StatCard(
                        title: "Overdue",
                        value: vm.summary.overdue,
                        subtitle: "Jobs",
                        accentColor: .red
                    )
                }
            }
        }
    }

    // MARK: - Upcoming

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Dispatches")
                .font(.title3)
                .fontWeight(.semibold)

            if vm.state == .loading {
                ForEach(0..<4, id: \.self) { _ in
                    skeletonRow
                }
            } else if case .error(let msg) = vm.state {
                errorCard(msg)
            } else if vm.summary.upcoming.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.summary.upcoming) { job in
                        UpcomingJobRow(job: job)

                        if job.id != vm.summary.upcoming.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("Nothing due in the next 7 days.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") { Task { await vm.refresh() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Skeletons

    private var skeletonCard: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.quaternary)
            .frame(width: 130, height: 100)
    }

    private var skeletonRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 140, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 100, height: 12)
            }
            Spacer()
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 40, height: 12)
        }
        .padding(.vertical, 10)
    }
}

#Preview {
    DashboardView()
}
