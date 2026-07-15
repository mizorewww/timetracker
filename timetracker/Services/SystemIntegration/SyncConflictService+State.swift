import Foundation
import OSLog

extension SyncConflictService {
    private static let stateLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker",
        category: "SyncConflictState"
    )

    func loadState() throws -> SyncConflictState {
        try withExclusiveStateAccess {
            try loadStateWithoutLock()
        }
    }

    private func loadStateWithoutLock() throws -> SyncConflictState {
        let url = try stateURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            var recoveredState = SyncConflictState()
            if var backup = try loadPendingForcedUploadSnapshotWithoutLock(),
               backup.hasProtectableUserContent {
                if backup.removeExcludedPreferences() {
                    try savePendingForcedUploadSnapshotWithoutLock(backup)
                }
                // The mirror is consulted only when authoritative state is
                // absent; a valid state with nil pending data suppresses it.
                recoveredState.pendingForcedUploadSnapshot = backup
                try saveStateWithoutLock(recoveredState)
            }
            return recoveredState
        }

        let data = try Data(contentsOf: url)
        let decodedState: SyncConflictState
        do {
            decodedState = try JSONDecoder().decode(SyncConflictState.self, from: data)
        } catch {
            let quarantineURL = try quarantineCorruptFile(
                at: url,
                data: data,
                prefix: Self.corruptStateFilePrefix
            )
            Self.stateLogger.error(
                "Quarantined corrupt sync state at \(quarantineURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw SyncConflictStateFileError.corruptStateQuarantined
        }

        var state = decodedState
        let removedExcludedPreferences = try state.removeExcludedPreferences()
        let prunedExportCheckpoints = state.pruneCloudExportCheckpoints()
        if removedExcludedPreferences || prunedExportCheckpoints {
            try saveStateWithoutLock(state)
        } else {
            try synchronizePendingForcedUploadMirrorWithoutLock(with: state)
        }
        return state
    }

    func saveState(_ state: SyncConflictState) throws {
        try withExclusiveStateAccess {
            try saveStateWithoutLock(state)
        }
    }

    private func saveStateWithoutLock(_ state: SyncConflictState) throws {
        let url = try stateURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: url, options: [.atomic])
        try protectSensitiveFileIfSupported(at: url)
        try synchronizePendingForcedUploadMirrorWithoutLock(with: state)
    }

    func loadPendingForcedUploadSnapshot() throws -> SyncDataSnapshot? {
        try withExclusiveStateAccess {
            try loadStateWithoutLock().pendingForcedUploadSnapshot
        }
    }

    private func synchronizePendingForcedUploadMirrorWithoutLock(
        with state: SyncConflictState
    ) throws {
        if let snapshot = state.pendingForcedUploadSnapshot,
           snapshot.hasProtectableUserContent {
            try savePendingForcedUploadSnapshotWithoutLock(snapshot)
        } else {
            try removePendingForcedUploadSnapshotWithoutLock()
        }
    }

    private func savePendingForcedUploadSnapshotWithoutLock(
        _ snapshot: SyncDataSnapshot
    ) throws {
        let url = try pendingForcedUploadSnapshotURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: [.atomic])
        try protectSensitiveFileIfSupported(at: url)
    }

    private func removePendingForcedUploadSnapshotWithoutLock() throws {
        let url = try pendingForcedUploadSnapshotURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func loadPendingForcedUploadSnapshotWithoutLock() throws -> SyncDataSnapshot? {
        let url = try pendingForcedUploadSnapshotURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(SyncDataSnapshot.self, from: data)
        } catch {
            let quarantineURL = try quarantineCorruptFile(
                at: url,
                data: data,
                prefix: Self.corruptPendingSnapshotFilePrefix
            )
            Self.stateLogger.error(
                "Quarantined corrupt recovery snapshot at \(quarantineURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    static func loadPendingForcedUploadSnapshot(at url: URL) throws -> SyncDataSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(
            SyncDataSnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    private func quarantineCorruptFile(
        at url: URL,
        data: Data,
        prefix: String
    ) throws -> URL {
        let quarantineURL = url.deletingLastPathComponent().appendingPathComponent(
            prefix + UUID().uuidString + ".json"
        )
        do {
            try FileManager.default.moveItem(at: url, to: quarantineURL)
        } catch {
            try data.write(to: quarantineURL, options: [.atomic])
            try FileManager.default.removeItem(at: url)
        }
        try protectSensitiveFileIfSupported(at: quarantineURL)
        return quarantineURL
    }

    private func protectSensitiveFileIfSupported(at url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}
