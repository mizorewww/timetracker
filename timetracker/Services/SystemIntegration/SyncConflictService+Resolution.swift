import SwiftData

extension SyncConflictService {
    func resolve(_ resolution: SyncConflictResolution, context: ModelContext) throws {
        try withExclusiveStateAccess {
            try resolveWithLockedState(resolution, context: context)
        }
    }

    private func resolveWithLockedState(
        _ resolution: SyncConflictResolution,
        context: ModelContext
    ) throws {
        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else {
            switch resolution {
            case .uploadLocal:
                _ = try forceUploadLocalData(context: context)
            case .downloadCloud:
                _ = try acceptCurrentCloudData(context: context)
            }
            return
        }

        var state = try loadState()
        state.advanceSyncEpoch()
        switch resolution {
        case .uploadLocal:
            guard let localSnapshot = state.localSnapshot else {
                throw SyncConflictError.localSnapshotMissing
            }
            try localSnapshot.restoreAsLocalWinner(context: context)
            let resolvedSnapshot = try SyncDataSnapshot.capture(context: context)
            state.localSnapshot = resolvedSnapshot
            state.localFingerprint = try resolvedSnapshot.fingerprint()
            state.advanceLocalGeneration()
            state.pendingForcedUploadSnapshot = resolvedSnapshot
        case .downloadCloud:
            guard let cloudSnapshot = state.pendingCloudSnapshot else {
                throw SyncConflictError.cloudSnapshotMissing
            }
            try cloudSnapshot.restoreAsLocalWinner(context: context)
            let restoredSnapshot = try SyncDataSnapshot.capture(context: context)
            let fingerprint = try restoredSnapshot.fingerprint()
            state.localSnapshot = restoredSnapshot
            state.localFingerprint = fingerprint
            state.baseFingerprint = fingerprint
            state.baseAcknowledgedGeneration = state.localGeneration
            state.pendingForcedUploadSnapshot = nil
        }
        state.clearPendingConflict()
        try saveState(state)
    }
}
