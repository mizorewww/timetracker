import SwiftData

extension SyncConflictService {
    func stageCurrentLocalSnapshotForCloudEnablement(
        context: ModelContext
    ) throws -> SyncRecoveryResult {
        try withExclusiveStateAccess {
            let snapshot = try SyncDataSnapshot.capture(context: context)
            if snapshot.hasProtectableUserContent {
                return try forceUploadLocalData(context: context)
            }
            return try acceptCurrentCloudData(context: context)
        }
    }

    func forceUploadLocalData(context: ModelContext) throws -> SyncRecoveryResult {
        try withExclusiveStateAccess {
            try forceUploadLocalDataWithLockedState(context: context)
        }
    }

    private func forceUploadLocalDataWithLockedState(
        context: ModelContext
    ) throws -> SyncRecoveryResult {
        var state = try loadState()
        state.advanceSyncEpoch()
        let currentSnapshot = try SyncDataSnapshot.capture(context: context)
        let snapshot = snapshotForForcedUpload(currentSnapshot: currentSnapshot, state: state)
        let isCloudActive = AppCloudSync.persistenceMode == AppCloudSync.modeICloud
        let shouldRestoreRecovery = !isCloudActive &&
            !currentSnapshot.hasProtectableUserContent &&
            snapshot.hasProtectableUserContent

        let exportedSnapshot: SyncDataSnapshot
        if isCloudActive || shouldRestoreRecovery {
            try snapshot.restoreAsLocalWinner(context: context)
            exportedSnapshot = try SyncDataSnapshot.capture(context: context)
        } else {
            exportedSnapshot = snapshot
        }
        guard exportedSnapshot.hasProtectableUserContent else {
            throw SyncConflictError.uploadSnapshotMissing
        }

        state.pendingForcedUploadSnapshot = exportedSnapshot
        state.localSnapshot = exportedSnapshot
        state.localFingerprint = try exportedSnapshot.fingerprint()
        state.advanceLocalGeneration()
        state.clearPendingConflict()
        try saveState(state)
        if !isCloudActive {
            AppCloudSync.requestCloudUploadReset()
        }
        return isCloudActive ? .appliedImmediately : .queuedForNextLaunch
    }

    func acceptCurrentCloudData(context: ModelContext) throws -> SyncRecoveryResult {
        try withExclusiveStateAccess {
            var state = try loadState()
            state.advanceSyncEpoch()
            state.baseFingerprint = nil
            state.localSnapshot = nil
            state.localFingerprint = nil
            state.pendingForcedUploadSnapshot = nil
            state.clearPendingConflict()
            try saveState(state)
            AppCloudSync.requestCloudDownloadReset()
            return .queuedForNextLaunch
        }
    }

    private func snapshotForForcedUpload(
        currentSnapshot: SyncDataSnapshot,
        state: SyncConflictState
    ) -> SyncDataSnapshot {
        if currentSnapshot.hasProtectableUserContent {
            return currentSnapshot
        }
        if let pendingSnapshot = state.pendingForcedUploadSnapshot,
           pendingSnapshot.hasProtectableUserContent {
            return pendingSnapshot
        }
        if let localSnapshot = state.localSnapshot,
           localSnapshot.hasProtectableUserContent {
            return localSnapshot
        }
        return currentSnapshot
    }
}
