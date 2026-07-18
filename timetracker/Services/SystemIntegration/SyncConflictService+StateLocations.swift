import Foundation

extension SyncConflictService {
    nonisolated func stateURL() throws -> URL {
        if let stateURLOverride {
            return stateURLOverride
        }
        return try Self.defaultStateURL()
    }

    nonisolated func pendingForcedUploadSnapshotURL() throws -> URL {
        if let stateURLOverride {
            return stateURLOverride
                .deletingLastPathComponent()
                .appendingPathComponent(Self.pendingForcedUploadSnapshotFileName)
        }
        return try Self.defaultPendingForcedUploadSnapshotURL()
    }

    nonisolated func stateLockURL() throws -> URL {
        Self.stateLockURL(for: try stateURL())
    }

    /// Derives the durable root from the exact spelling of a managed URL.
    ///
    /// On iOS the same container can be reported as either `/var/...` or
    /// `/private/var/...`. Keeping the target and root on one spelling avoids
    /// treating those aliases as unrelated paths before canonicalization.
    /// Production uses the stable Application Support parent so a retry can
    /// replay the directory sync that publishes `TimeTrackerSync`. Test and
    /// diagnostic overrides own their explicitly supplied state directory.
    nonisolated func stateDurableRootURL(for managedURL: URL) -> URL {
        let stateDirectory = managedURL.deletingLastPathComponent()
        if stateURLOverride != nil {
            return stateDirectory
        }
        return stateDirectory.deletingLastPathComponent()
    }

    nonisolated static func stateLockURL(for stateURL: URL) -> URL {
        stateURL.deletingLastPathComponent().appendingPathComponent(
            ".\(stateURL.lastPathComponent).lock"
        )
    }

    nonisolated static func defaultStateURL() throws -> URL {
        try defaultStateDirectoryURL().appendingPathComponent(Self.stateFileName)
    }

    nonisolated static func defaultPendingForcedUploadSnapshotURL() throws -> URL {
        try defaultStateDirectoryURL().appendingPathComponent(
            Self.pendingForcedUploadSnapshotFileName
        )
    }

    nonisolated static func defaultStateDirectoryURL() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return baseURL.appendingPathComponent(Self.stateDirectoryName, isDirectory: true)
    }
}
