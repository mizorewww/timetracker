import Foundation
import OSLog

extension AppCloudSync {
    static func requestCloudRetryAfterRecovery() {
        AppDemoDataConfiguration.disableLocalDemoStoreForCloudSync()
        AppDefaults.shared.set(true, forKey: enabledKey)
        AppDefaults.shared.removeObject(forKey: errorKey)
    }

    static func requestCloudUploadReset() {
        let defaults = AppDefaults.shared
        defaults.set(true, forKey: pendingCloudUploadResetKey)
        defaults.removeObject(forKey: pendingCloudDownloadResetKey)
        defaults.removeObject(forKey: queuedCloudReconciliationKey)
        defaults.removeObject(forKey: activeCloudReconciliationKey)
        defaults.removeObject(forKey: activeCloudDownloadRecoveryKey)
        requestCloudRetryAfterRecovery()
        logger.warning("Queued CloudKit upload recovery reset")
    }

    static func requestCloudDownloadReset() {
        let defaults = AppDefaults.shared
        defaults.set(true, forKey: pendingCloudDownloadResetKey)
        defaults.removeObject(forKey: pendingCloudUploadResetKey)
        defaults.removeObject(forKey: queuedCloudReconciliationKey)
        defaults.removeObject(forKey: activeCloudReconciliationKey)
        defaults.removeObject(forKey: cloudRecoveryStoreResetKey)
        defaults.removeObject(forKey: activeCloudDownloadRecoveryKey)
        requestCloudRetryAfterRecovery()
        logger.warning("Queued CloudKit download recovery reset")
    }

    static func requestCloudReconciliationReset() {
        let defaults = AppDefaults.shared
        // Publish the reconciliation discriminator first. Background readers
        // must never observe the upload marker alone and infer that this is an
        // explicit replace-cloud recovery.
        defaults.set(true, forKey: queuedCloudReconciliationKey)
        defaults.set(true, forKey: pendingCloudUploadResetKey)
        defaults.removeObject(forKey: pendingCloudDownloadResetKey)
        defaults.removeObject(forKey: activeCloudReconciliationKey)
        defaults.removeObject(forKey: activeCloudDownloadRecoveryKey)
        requestCloudRetryAfterRecovery()
        logger.warning("Queued CloudKit reconciliation reset")
    }

    @discardableResult
    static func requestCloudReconciliationReset(
        ifCurrentPolicyMatches expectedPolicy:
        SyncLocalMutationRecordingPolicy
    ) -> Bool {
        let currentPolicy =
            SyncLocalMutationRecordingPolicy.current()
        guard currentPolicy == expectedPolicy,
              currentPolicy
              .shouldRequestCloudReconciliationReset
        else {
            return false
        }
        requestCloudReconciliationReset()
        return true
    }

    /// Reconstructs a missing defaults marker from the separately persisted
    /// protected branch before the SwiftData store is attached to CloudKit.
    /// This closes the crash window between saving the recovery snapshot and
    /// queuing the clean-store reset.
    @discardableResult
    static func preparePendingCloudRecoveryReset(
        hasProtectedSnapshot: (() -> Bool)? = nil,
        loadIntent: (() throws -> SyncPendingLocalIntent?)? = nil,
        hasCompletedImportSession: (() throws -> Bool)? = nil
    ) -> Bool {
        let snapshotProbe = hasProtectedSnapshot ?? {
            SyncConflictService.hasDefaultPendingForcedUploadBackup()
        }
        guard snapshotProbe() else {
            return false
        }

        let intentLoader = loadIntent ?? {
            try SyncConflictService().persistedPendingLocalIntent()
        }
        let intent = (try? intentLoader()) ?? .reconcileWithCloud
        switch intent {
        case .reconcileWithCloud:
            let sessionProbe = hasCompletedImportSession ?? {
                try SyncConflictService().hasCompletedCloudRecoveryImportSession(
                    kind: .reconcileWithCloud
                )
            }
            if isCloudReconciliationActive,
               (try? sessionProbe()) == true
            {
                return true
            }
            requestCloudReconciliationReset()
        case .explicitlyReplaceCloud:
            completeCloudReconciliation()
            requestCloudUploadReset()
        }
        return true
    }

    /// An interrupted download must either retain the fresh-store import
    /// journal or rebuild the store again. Never attach a pre-existing cache
    /// to an unjournaled download recovery and infer that it is hydrated.
    static func prepareInterruptedCloudDownloadRecovery(
        hasCompletedImportSession: (() throws -> Bool)? = nil
    ) {
        guard isCloudDownloadRecoveryActive else { return }
        let sessionProbe = hasCompletedImportSession ?? {
            try SyncConflictService().hasCompletedCloudRecoveryImportSession(
                kind: .downloadCloud
            )
        }
        guard (try? sessionProbe()) != true else { return }
        requestCloudDownloadReset()
    }
}
