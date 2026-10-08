import CoreData
import SwiftData

extension SyncConflictService {
    /// Closes the process-termination window between a successful local-store
    /// commit and its post-commit protected-snapshot write. The caller must run
    /// this while the fallback store still exists and before any recovery reset.
    func refreshProtectedLocalFallbackSnapshotBeforeReset(
        context: ModelContext
    ) throws {
        guard AppCloudSync.shouldRefreshLocalFallbackRecoverySnapshotBeforeReset else {
            return
        }
        _ = try recordLocalMutation(context: context, events: [.fullSync])
    }

    func stageCurrentLocalSnapshotForCloudEnablement(
        context: ModelContext
    ) throws -> SyncRecoveryResult {
        try requireNoAttachedCloudRecovery()
        return try withLockedFreshStoreContext(context: context) { lockedContext in
            try withExclusiveStateAccess {
                let snapshot = try SyncDataSnapshot.capture(context: lockedContext)
                if snapshot.hasProtectableUserContent {
                    var state = try loadState()
                    state.advanceSyncEpoch()
                    state.localSnapshot = snapshot
                    state.localFingerprint = try snapshot.fingerprint()
                    state.advanceLocalGeneration()
                    state.pendingForcedUploadSnapshot = snapshot
                    state.pendingLocalIntent = .reconcileWithCloud
                    state.clearCloudRecoveryImportSession()
                    try saveState(state)
                    AppCloudSync.requestCloudReconciliationReset()
                    return .queuedForNextLaunch
                }
                return try acceptCurrentCloudDataWithLockedState()
            }
        }
    }

    func forceUploadLocalData(context: ModelContext) throws -> SyncRecoveryResult {
        try requireNoAttachedCloudRecovery()
        return try withLockedFreshStoreContext(context: context) { lockedContext in
            try withExclusiveStateAccess {
                try forceUploadLocalDataWithLockedState(context: lockedContext)
            }
        }
    }

    /// Caller must already hold the store lock followed by the sync-state lock.
    func forceUploadLocalDataWithLockedState(
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
        state.pendingLocalIntent = .explicitlyReplaceCloud
        state.clearCloudRecoveryImportSession()
        state.localSnapshot = exportedSnapshot
        state.localFingerprint = try exportedSnapshot.fingerprint()
        state.advanceLocalGeneration()
        state.clearPendingConflict()
        try saveState(state)
        AppCloudSync.completeCloudReconciliation()
        if !isCloudActive {
            AppCloudSync.requestCloudUploadReset()
        }
        return isCloudActive ? .appliedImmediately : .queuedForNextLaunch
    }

    func acceptCurrentCloudData(context _: ModelContext) throws -> SyncRecoveryResult {
        try requireNoAttachedCloudRecovery()
        return try withExclusiveStateAccess {
            try acceptCurrentCloudDataWithLockedState()
        }
    }

    /// Caller must already hold the sync-state lock. A surrounding store lock
    /// is required when this participates in a store-backed resolution flow.
    func acceptCurrentCloudDataWithLockedState() throws -> SyncRecoveryResult {
        // Persist the destructive restart intent before clearing the only
        // protected branch. A crash at any later instruction must still force
        // the next launch to rebuild from CloudKit instead of exporting local.
        AppCloudSync.requestCloudDownloadReset()
        var state = try loadState()
        state.advanceSyncEpoch()
        state.baseFingerprint = nil
        state.localSnapshot = nil
        state.localFingerprint = nil
        state.cloudDownloadRecoveryCompleted = nil
        state.clearCloudRecoveryImportSession()
        state.clearPendingLocalRecovery()
        state.clearPendingConflict()
        try saveState(state)
        AppCloudSync.completeCloudReconciliation()
        return .queuedForNextLaunch
    }

    private func snapshotForForcedUpload(
        currentSnapshot: SyncDataSnapshot,
        state: SyncConflictState
    ) -> SyncDataSnapshot {
        if currentSnapshot.hasProtectableUserContent {
            return currentSnapshot
        }
        if let pendingSnapshot = state.pendingForcedUploadSnapshot,
           pendingSnapshot.hasProtectableUserContent
        {
            return pendingSnapshot
        }
        if let localSnapshot = state.localSnapshot,
           localSnapshot.hasProtectableUserContent
        {
            return localSnapshot
        }
        return currentSnapshot
    }
}

extension CloudRecoveryContainerEventReceipt {
    init?(event: NSPersistentCloudKitContainer.Event) {
        guard let completedAt = event.endDate else { return nil }

        let kind: EventKind
        switch event.type {
        case .setup:
            kind = .setup
        case .import:
            kind = .import
        case .export:
            kind = .export
        @unknown default:
            return nil
        }

        self.init(
            storeIdentifier: event.storeIdentifier,
            kind: kind,
            startedAt: event.startDate,
            completedAt: completedAt,
            succeeded: event.succeeded
        )
    }
}

extension SyncConflictService {
    func beginCloudRecoveryImportSession(
        kind: CloudRecoveryImportKind,
        startedAt: Date = Date()
    ) throws {
        try withExclusiveStateAccess {
            var state = try loadState()
            state.cloudRecoveryImportSession = CloudRecoveryImportSession(
                id: UUID(),
                kind: kind,
                startedAt: startedAt
            )
            state.cloudDownloadRecoveryCompleted = nil
            try saveState(state)
        }
    }

    func recordCloudRecoveryContainerEvent(
        _ receipt: CloudRecoveryContainerEventReceipt
    ) throws {
        try withExclusiveStateAccess {
            var state = try loadState()
            guard var session = state.cloudRecoveryImportSession else { return }
            let previousSession = session
            session.record(receipt)
            guard session != previousSession else { return }
            state.cloudRecoveryImportSession = session
            try saveState(state)
        }
    }

    func hasCompletedCloudRecoveryImportSession(
        kind: CloudRecoveryImportKind
    ) throws -> Bool {
        guard let session = try loadState().cloudRecoveryImportSession else {
            return false
        }
        return session.kind == kind && session.hasCompletedInitialImport
    }

    /// True when the active recovery intent has observed a complete fresh-store
    /// Setup-to-import barrier for the matching session kind.
    func cloudRecoveryImportIsReady(in state: SyncConflictState) -> Bool {
        guard let session = state.cloudRecoveryImportSession,
              session.hasCompletedInitialImport
        else {
            return false
        }
        if AppCloudSync.isCloudDownloadRecoveryActive {
            return session.kind == .downloadCloud
        }
        if AppCloudSync.isCloudReconciliationActive {
            return session.kind == .reconcileWithCloud
        }
        return false
    }
}
