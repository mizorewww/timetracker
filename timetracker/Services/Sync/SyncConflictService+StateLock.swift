import Foundation

extension SyncConflictService {
    /// `lockf` coordinates the app, widgets, and Shortcuts processes. A
    /// recursive in-process lock is also necessary because POSIX record locks
    /// are associated with the process and state helpers deliberately nest
    /// locked transactions.
    private static let stateLockRegistry = PathFileLockRegistry(
        mechanism: .lockf
    )

    nonisolated func withExclusiveStateAccess<Result>(
        _ operation: () throws -> Result
    ) throws -> Result {
        let lockURL = try stateLockURL()
        return try Self.stateLockRegistry
            .lock(for: lockURL)
            .withExclusiveAccess(operation)
    }

    nonisolated static func removeDefaultState() throws {
        let stateURL = try defaultStateURL()
        let backupURL = try defaultPendingForcedUploadSnapshotURL()
        let lockURL = stateLockURL(for: stateURL)
        let durableRootURL = stateURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let durableFile = DurableLocalFile()
        try stateLockRegistry
            .lock(for: lockURL)
            .withExclusiveAccess {
                // If interrupted, a still-present authoritative state remains
                // preferable to an orphaned recovery mirror. Each removal is
                // durably published before proceeding to the next file.
                try durableFile.removeIfPresent(
                    at: backupURL,
                    durableRootURL: durableRootURL
                )
                try durableFile.removeIfPresent(
                    at: stateURL,
                    durableRootURL: durableRootURL
                )
                for snapshotURL in SyncConflictService.allConflictSnapshotSlotURLs(for: stateURL) {
                    try durableFile.removeIfPresent(
                        at: snapshotURL,
                        durableRootURL: durableRootURL
                    )
                }
            }
    }
}
