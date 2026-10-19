import CabinetDesign
import SwiftUI

/// Compact badge showing pending/conflict counts and offline state.
/// Lives in the box screen's top bar: quiet glyphs with a count.
struct SyncBadgeView: View {
    let pendingCount: Int
    let conflictCount: Int
    let isOnline: Bool

    var body: some View {
        HStack(spacing: PaperSpace.s) {
            if !isOnline {
                PaperIcon(.offline, size: 18, color: PaperColor.ember)
                    .accessibilityLabel("Offline")
            }
            if pendingCount > 0 {
                HStack(spacing: 3) {
                    PaperIcon(.sync, size: 16, color: PaperColor.secondary)
                    Text("\(pendingCount)").paperType(.footnote, numeric: true).foregroundStyle(PaperColor.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(pendingCount) waiting to sync")
            }
            if conflictCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(PaperColor.danger).frame(width: 7, height: 7)
                    Text("\(conflictCount)").paperType(.footnote, numeric: true).foregroundStyle(PaperColor.danger)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(conflictCount) need checking")
            }
        }
    }
}

/// Shown above the scan button when offline.
struct OfflineBannerView: View {
    var body: some View {
        Notice(text: "Offline. Scans are kept on this device and sync when the connection's back.",
               tone: .soon, glyph: .offline)
    }
}
