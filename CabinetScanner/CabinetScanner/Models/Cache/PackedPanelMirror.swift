import Foundation
import SwiftData

/// Local mirror of "panels already packed in this consignment" — populated
/// from the server on box-open and updated optimistically as the user scans.
/// Used by ScanCacheService for instant duplicate detection.
@Model
final class PackedPanelMirror {
    @Attribute(.unique) var compoundKey: String

    var consignmentId: String
    var panelUid: String
    var boxId: String
    var syncedAt: Date

    init(consignmentId: String, panelUid: String, boxId: String, syncedAt: Date = .now) {
        self.compoundKey = "\(consignmentId)|\(panelUid)"
        self.consignmentId = consignmentId
        self.panelUid = panelUid
        self.boxId = boxId
        self.syncedAt = syncedAt
    }
}
