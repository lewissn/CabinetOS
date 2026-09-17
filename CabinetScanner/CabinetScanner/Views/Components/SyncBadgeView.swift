import SwiftUI

/// Compact badge showing pending/conflict counts and offline state.
/// Designed to live in the BoxDetailView toolbar or header.
struct SyncBadgeView: View {
    let pendingCount: Int
    let conflictCount: Int
    let isOnline: Bool

    var body: some View {
        HStack(spacing: 6) {
            if !isOnline {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
            }
            if pendingCount > 0 {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("\(pendingCount)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.blue.opacity(0.15))
                .clipShape(Capsule())
            }
            if conflictCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text("\(conflictCount)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.red.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }
}

/// A persistent banner shown above the scan button when offline.
struct OfflineBannerView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline — scans will sync when connection returns")
                .font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.orange.opacity(0.18))
        .foregroundStyle(.orange)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
