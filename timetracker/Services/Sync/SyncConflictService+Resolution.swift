import Foundation
import SwiftData

extension SyncConflictService {
    func resolveSyncConflict(
        expectedConflictID: UUID?,
        resolution: SyncConflictResolution,
        context: ModelContext
    ) throws -> SyncConflictResolutionResult {
        try requireNoAttachedCloudRecovery()
        return try withLockedFreshStoreContext(context: context) { lockedContext in
            try withExclusiveStateAccess {
                try resolveWithLockedState(
                    expectedConflictID: expectedConflictID,
                    resolution: resolution,
                    context: lockedContext
                )
            }
        }
    }

    private func resolveWithLockedState(
        expectedConflictID: UUID?,
        resolution: SyncConflictResolution,
        context: ModelContext
    ) throws -> SyncConflictResolutionResult {
        var state = try loadState()
        guard state.pendingConflictID == expectedConflictID else {
            return .conflictChanged
        }

        guard expectedConflictID != nil else {
            let recoveryResult: SyncRecoveryResult = switch resolution {
            case .uploadLocal:
                try forceUploadLocalDataWithLockedState(
                    context: context
                )
            case .downloadCloud:
                try acceptCurrentCloudDataWithLockedState()
            }
            return Self.resolutionResult(for: recoveryResult)
        }

        guard AppCloudSync.persistenceMode == AppCloudSync.modeICloud else {
            let recoveryResult: SyncRecoveryResult = switch resolution {
            case .uploadLocal:
                try forceUploadLocalDataWithLockedState(
                    context: context
                )
            case .downloadCloud:
                try acceptCurrentCloudDataWithLockedState()
            }
            return Self.resolutionResult(for: recoveryResult)
        }

        state.advanceSyncEpoch()
        state.clearCloudRecoveryImportSession()
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
            state.pendingLocalIntent = .explicitlyReplaceCloud
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
            state.clearPendingLocalRecovery()
        }
        state.clearPendingConflict()
        try saveState(state)
        AppCloudSync.completeCloudReconciliation()
        return .appliedImmediately
    }

    private static func resolutionResult(
        for recoveryResult: SyncRecoveryResult
    ) -> SyncConflictResolutionResult {
        switch recoveryResult {
        case .appliedImmediately:
            .appliedImmediately
        case .queuedForNextLaunch:
            .queuedForNextLaunch
        }
    }
}
