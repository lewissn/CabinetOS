import Foundation
import SwiftData

/// Singleton ModelContainer for the offline scan cache.
///
/// Schema v1: CachedPanelRegistry, CachedRegistryMeta, PackedPanelMirror,
/// PendingScan. Future schema changes should use VersionedSchema +
/// SchemaMigrationPlan; do not add unique attributes to existing models
/// without a migration step.
enum ScanCacheContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            CachedPanelRegistry.self,
            CachedRegistryMeta.self,
            PackedPanelMirror.self,
            PendingScan.self,
        ])
        let config = ModelConfiguration(
            "CabinetScannerCache.v1",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // If the on-disk store can't be opened (e.g. schema mismatch on a
            // dev build), fall back to in-memory rather than crashing the app.
            // Pending scans are lost but the app stays usable.
            print("[ScanCacheContainer] Falling back to in-memory store: \(error)")
            let memConfig = ModelConfiguration("CabinetScannerCache.v1.mem", schema: schema, isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: [memConfig])
        }
    }()
}
