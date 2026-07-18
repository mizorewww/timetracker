import Foundation

nonisolated struct SyncConflictLocalStateByteLimits: Equatable, Sendable {
    let maximumStateFileByteCount: Int
    let maximumRecoverySnapshotFileByteCount: Int

    static var production: Self {
        Self(
            maximumStateFileByteCount: SyncConflictService.maximumStateFileByteCount,
            maximumRecoverySnapshotFileByteCount:
                SyncConflictService.maximumRecoverySnapshotFileByteCount
        )
    }

    init(
        maximumStateFileByteCount: Int,
        maximumRecoverySnapshotFileByteCount: Int
    ) {
        precondition(maximumStateFileByteCount >= 0)
        precondition(maximumRecoverySnapshotFileByteCount >= 0)
        self.maximumStateFileByteCount = maximumStateFileByteCount
        self.maximumRecoverySnapshotFileByteCount = maximumRecoverySnapshotFileByteCount
    }
}

enum SyncConflictLocalStateWriteError: Error, Equatable {
    case stateExceedsMaximumByteCount(actualByteCount: Int, maximumByteCount: Int)
    case recoverySnapshotExceedsMaximumByteCount(
        actualByteCount: Int,
        maximumByteCount: Int
    )
}

private enum PendingForcedUploadMirrorMutation {
    case save(Data)
    case remove
}

extension SyncConflictService {
    func saveState(_ state: SyncConflictState) throws {
        try withExclusiveStateAccess {
            try saveStateWithoutLock(state)
        }
    }

    func saveStateWithoutLock(_ state: SyncConflictState) throws {
        // Preflight every payload before resolving paths, creating directories,
        // or replacing any valid file. A/B slot writes occur before the manifest
        // commit, so an interrupted write cannot invalidate its old authority.
        let manifestWrite = try prepareManifestWrite(for: state)
        let mirrorMutation = try pendingForcedUploadMirrorMutation(for: state)

        try writeSnapshotSlotsWithoutLock(manifestWrite.snapshotSlots)
        let url = try stateURL()
        try localStateFile.write(
            manifestWrite.data,
            to: url,
            durableRootURL: stateDurableRootURL(for: url)
        )
        try applyPendingForcedUploadMirrorMutation(mirrorMutation)
        try removeUnreferencedSnapshotSlotsWithoutLock(
            retaining: manifestWrite.manifest.snapshotReferences
        )
    }

    func synchronizePendingForcedUploadMirrorWithoutLock(
        with state: SyncConflictState
    ) throws {
        try applyPendingForcedUploadMirrorMutation(
            pendingForcedUploadMirrorMutation(for: state)
        )
    }

    func savePendingForcedUploadSnapshotWithoutLock(
        _ snapshot: SyncDataSnapshot
    ) throws {
        let data = try encodedRecoverySnapshotForWrite(snapshot)
        try writePendingForcedUploadSnapshotWithoutLock(data)
    }

    private func pendingForcedUploadMirrorMutation(
        for state: SyncConflictState
    ) throws -> PendingForcedUploadMirrorMutation {
        guard let snapshot = state.pendingForcedUploadSnapshot,
              snapshot.hasProtectableUserContent else {
            return .remove
        }
        return .save(try encodedRecoverySnapshotForWrite(snapshot))
    }

    private func encodedRecoverySnapshotForWrite(
        _ snapshot: SyncDataSnapshot
    ) throws -> Data {
        let data = try Self.sortedJSONEncoder().encode(snapshot)
        try validateRecoverySnapshotWriteByteCount(data.count)
        return data
    }

    func validateRecoverySnapshotWriteByteCount(_ byteCount: Int) throws {
        guard byteCount <= localStateByteLimits.maximumRecoverySnapshotFileByteCount else {
            throw SyncConflictLocalStateWriteError.recoverySnapshotExceedsMaximumByteCount(
                actualByteCount: byteCount,
                maximumByteCount: localStateByteLimits.maximumRecoverySnapshotFileByteCount
            )
        }
    }

    private func applyPendingForcedUploadMirrorMutation(
        _ mutation: PendingForcedUploadMirrorMutation
    ) throws {
        switch mutation {
        case let .save(data):
            try writePendingForcedUploadSnapshotWithoutLock(data)
        case .remove:
            try removePendingForcedUploadSnapshotWithoutLock()
        }
    }

    private func writePendingForcedUploadSnapshotWithoutLock(_ data: Data) throws {
        // Keep this check at the final independent write boundary as well as at
        // the combined state preflight boundary.
        try validateRecoverySnapshotWriteByteCount(data.count)
        let url = try pendingForcedUploadSnapshotURL()
        try localStateFile.write(
            data,
            to: url,
            durableRootURL: stateDurableRootURL(for: url)
        )
    }

    private func removePendingForcedUploadSnapshotWithoutLock() throws {
        let url = try pendingForcedUploadSnapshotURL()
        try localStateFile.removeIfPresent(
            at: url,
            durableRootURL: stateDurableRootURL(for: url)
        )
    }

    static func sortedJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
