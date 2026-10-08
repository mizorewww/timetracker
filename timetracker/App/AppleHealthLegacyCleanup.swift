import Foundation

/// One-time cleanup of artifacts left behind by the removed Apple Health
/// integration.
///
/// The device-local Health replica store sat next to the main user store and is
/// no longer opened by any code path. This runs on the real-app startup path
/// only; it is tolerate-absent, so the files are removed on the first launch of
/// a health-free build and the call is a no-op afterwards.
enum AppleHealthLegacyCleanup {
    static func runIfNeeded(defaults: UserDefaults = AppDefaults.shared) {
        let replicaStoreURL = AppCloudSync.persistentStoreURL
            .deletingLastPathComponent()
            .appendingPathComponent("AppleHealthReplica.store")
        for url in [
            replicaStoreURL,
            URL(fileURLWithPath: replicaStoreURL.path + "-shm"),
            URL(fileURLWithPath: replicaStoreURL.path + "-wal"),
        ] {
            try? FileManager.default.removeItem(at: url)
        }
        // Device-local keys owned by the removed timeline preference store.
        defaults.removeObject(forKey: "AppleHealthTimelineEnabled")
        defaults.removeObject(forKey: "AppleHealthTaskCatalogClearRecoveryIDs")
    }
}
