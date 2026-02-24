import SwiftUI

struct UpcomingJobRow: View {
    let job: UpcomingJob

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.customer)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                secondaryLine
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if job.isOverdue {
                badge("Overdue", color: .red)
            } else if job.isDueToday {
                badge("Today", color: .blue)
            } else {
                Text(formattedDueDate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    @ViewBuilder
    private var secondaryLine: some View {
        let parts = [
            "SO \(job.salesOrder)",
            job.shippingMethod
        ].compactMap { $0 }

        Text(parts.joined(separator: " \u{2022} "))
    }

    private var formattedDueDate: String {
        let cal = Calendar.london
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/London")

        if cal.isDate(job.dueDate, equalTo: Date(), toGranularity: .weekOfYear) {
            f.dateFormat = "EEE"
        } else {
            f.dateFormat = "d MMM"
        }
        return f.string(from: job.dueDate)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}
