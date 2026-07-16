import Foundation
import OSLog

extension SyncConflictService {
    nonisolated static var maximumStateFileByteCount: Int { 128 * 1_024 * 1_024 }
    nonisolated static var maximumRecoverySnapshotFileByteCount: Int { 64 * 1_024 * 1_024 }

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
                recoveredState.pendingLocalIntent = inferredPendingLocalIntentForRecoveryMirror()
                try saveStateWithoutLock(recoveredState)
            }
            return recoveredState
        }

        let data: Data
        do {
            data = try Self.boundedData(
                at: url,
                maximumByteCount: Self.maximumStateFileByteCount
            )
        } catch SyncConflictLocalStateReadError.exceedsMaximumByteCount {
            let quarantineURL = try quarantineCorruptFile(
                at: url,
                data: nil,
                prefix: Self.corruptStateFilePrefix
            )
            Self.stateLogger.error(
                "Quarantined oversized sync state at \(quarantineURL.path, privacy: .public)"
            )
            throw SyncConflictStateFileError.corruptStateQuarantined
        }
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

    /// The independent mirror predates intent persistence and intentionally
    /// remains snapshot-only for backwards compatibility. Defaults written
    /// before the destructive reset still distinguish explicit replacement
    /// from reconciliation when the authoritative state had to be quarantined.
    private func inferredPendingLocalIntentForRecoveryMirror() -> SyncPendingLocalIntent {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: AppCloudSync.queuedCloudReconciliationKey) ||
            defaults.bool(forKey: AppCloudSync.activeCloudReconciliationKey) {
            return .reconcileWithCloud
        }
        if defaults.bool(forKey: AppCloudSync.pendingCloudUploadResetKey) ||
            defaults.bool(forKey: AppCloudSync.cloudRecoveryStoreResetKey) {
            return .explicitlyReplaceCloud
        }
        // Legacy or incomplete metadata must never silently replace CloudKit.
        return .reconcileWithCloud
    }

    func loadPendingForcedUploadSnapshot() throws -> SyncDataSnapshot? {
        try withExclusiveStateAccess {
            try loadStateWithoutLock().pendingForcedUploadSnapshot
        }
    }

    private func loadPendingForcedUploadSnapshotWithoutLock() throws -> SyncDataSnapshot? {
        let url = try pendingForcedUploadSnapshotURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Self.boundedData(
                at: url,
                maximumByteCount: Self.maximumRecoverySnapshotFileByteCount
            )
        } catch SyncConflictLocalStateReadError.exceedsMaximumByteCount {
            let quarantineURL = try quarantineCorruptFile(
                at: url,
                data: nil,
                prefix: Self.corruptPendingSnapshotFilePrefix
            )
            Self.stateLogger.error(
                "Quarantined oversized recovery snapshot at \(quarantineURL.path, privacy: .public)"
            )
            return nil
        }
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
            from: boundedData(
                at: url,
                maximumByteCount: maximumRecoverySnapshotFileByteCount
            )
        )
    }

    private nonisolated static func boundedData(
        at url: URL,
        maximumByteCount: Int
    ) throws -> Data {
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard fileSize.map({ $0 <= maximumByteCount }) ?? true else {
            throw SyncConflictLocalStateReadError.exceedsMaximumByteCount
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumByteCount + 1) ?? Data()
        guard data.count <= maximumByteCount else {
            throw SyncConflictLocalStateReadError.exceedsMaximumByteCount
        }
        return data
    }

    private func quarantineCorruptFile(
        at url: URL,
        data: Data?,
        prefix: String
    ) throws -> URL {
        let quarantineURL = url.deletingLastPathComponent().appendingPathComponent(
            prefix + UUID().uuidString + ".json"
        )
        do {
            try FileManager.default.moveItem(at: url, to: quarantineURL)
        } catch {
            guard let data else { throw error }
            try data.write(to: quarantineURL, options: [.atomic])
            try FileManager.default.removeItem(at: url)
        }
        try protectSensitiveFileIfSupported(at: quarantineURL)
        return quarantineURL
    }

    func protectSensitiveFileIfSupported(at url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }
}

enum SyncConflictLocalStateReadError: Error { case exceedsMaximumByteCount }
