import Foundation
import SwiftData

/// One row of the cached BJS manifest panel registry. Populated on box-open and
/// used by ScanCacheService for in-memory O(1) scan validation.
///
/// `compoundKey` is `"\(manifestId)|\(panelUid)"` so the same panel UID can
/// (in theory) appear under different manifests without collision in the
/// local store.
@Model
final class CachedPanelRegistry {
    @Attribute(.unique) var compoundKey: String

    var manifestId: String
    var projectName: String
    var panelUid: String
    var cabinetName: String
    var partNumber: String
    var lengthMm: Int
    var widthMm: Int
    var thicknessMm: Int
    var material: String
    var fetchedAt: Date

    init(
        manifestId: String,
        projectName: String,
        panelUid: String,
        cabinetName: String,
        partNumber: String,
        lengthMm: Int,
        widthMm: Int,
        thicknessMm: Int,
        material: String,
        fetchedAt: Date = .now
    ) {
        self.compoundKey = "\(manifestId)|\(panelUid)"
        self.manifestId = manifestId
        self.projectName = projectName
        self.panelUid = panelUid
        self.cabinetName = cabinetName
        self.partNumber = partNumber
        self.lengthMm = lengthMm
        self.widthMm = widthMm
        self.thicknessMm = thicknessMm
        self.material = material
        self.fetchedAt = fetchedAt
    }
}
