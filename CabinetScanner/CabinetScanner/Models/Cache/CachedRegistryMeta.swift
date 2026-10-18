import Foundation
import SwiftData

/// Metadata about a cached panel registry per (manifest, project). Tracks the
/// server-issued ETag so the client can skip refetching when nothing has
/// changed, and acts as the cold-offline gate (if no row exists for a
/// manifest+project, the user must come online once before scanning).
@Model
final class CachedRegistryMeta {
    @Attribute(.unique) var compoundKey: String

    var manifestId: String
    var projectName: String
    var etag: String
    var fetchedAt: Date
    var panelCount: Int

    init(
        manifestId: String,
        projectName: String,
        etag: String,
        fetchedAt: Date = .now,
        panelCount: Int
    ) {
        self.compoundKey = "\(manifestId)|\(projectName)"
        self.manifestId = manifestId
        self.projectName = projectName
        self.etag = etag
        self.fetchedAt = fetchedAt
        self.panelCount = panelCount
    }
}
