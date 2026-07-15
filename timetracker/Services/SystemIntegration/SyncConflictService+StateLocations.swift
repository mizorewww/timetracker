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
