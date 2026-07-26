import SwiftUI

extension SettingsView {
    /// Surfaces the cleanup action whenever any synthetic row is present.
    ///
    /// Deliberately not gated on `allowsDemoDataCreation`: a Release build is
    /// exactly where the user needs to remove residue left behind by an earlier
    /// Debug install, and a cloud smoke-test probe counts as residue too.
    var hasDemoData: Bool {
        store.tasks.contains { SyntheticDataOrigin.marks($0.deviceID) } ||
            store.allSegments.contains { SyntheticDataOrigin.marks($0.deviceID) } ||
            store.pomodoroRuns.contains { SyntheticDataOrigin.marks($0.deviceID) } ||
            store.countdownEvents.contains { SyntheticDataOrigin.marks($0.deviceID) } ||
            store.checklistItems.contains { SyntheticDataOrigin.marks($0.deviceID) } ||
            store.inboxItems.contains { SyntheticDataOrigin.marks($0.deviceID) }
    }

    var currentStorageValue: String {
        store.preferences.cloudSyncEnabled
            ? (store.syncStatus.isCloudBacked ? "iCloud" : AppStrings.localized("settings.localWillRetryCloud"))
            : AppStrings.localized("settings.local")
    }

    var syncFeedback: SyncFeedback {
        if store.pendingSyncConflict != nil {
            return SyncFeedback(
                state: .conflict,
                title: AppStrings.localized("sync.state.conflict.title"),
                message: AppStrings.localized("sync.state.conflict.message")
            )
        }
        return store.syncStatus.feedback(
            preferences: store.preferences,
            isChecking: isCheckingSync,
            activity: store.lastSyncActivity
        )
    }

    func checkSyncStatus() {
        isCheckingSync = true
        syncOperationMessage = nil
        Task {
            _ = await store.refreshCloudAccountStatus()
            isCheckingSync = false
        }
    }

    func forceUploadLocalData(expectedConflictID: UUID?) {
        isCheckingSync = true
        syncOperationMessage = nil
        defer { isCheckingSync = false }
        do {
            let result = try store.resolveSyncConflict(
                expectedConflictID: expectedConflictID,
                resolution: .uploadLocal
            )
            switch result {
            case .appliedImmediately:
                if expectedConflictID != nil {
                    syncOperationMessage = AppStrings.localized("sync.forceUpload.conflictResolved")
                } else {
                    syncOperationMessage = AppStrings.localized("sync.forceUpload.started")
                }
            case .queuedForNextLaunch:
                syncOperationMessage = AppStrings.localized("sync.forceUpload.queued")
            case .conflictChanged:
                syncOperationMessage = AppStrings.localized("sync.conflict.error.changed")
            }
        } catch {
            presentSyncRecoveryError(error)
        }
    }

    func forceDownloadCloudData(expectedConflictID: UUID?) {
        isCheckingSync = true
        syncOperationMessage = nil
        Task {
            do {
                let result = try store.resolveSyncConflict(
                    expectedConflictID: expectedConflictID,
                    resolution: .downloadCloud
                )
                switch result {
                case .appliedImmediately:
                    if expectedConflictID != nil {
                        syncOperationMessage = AppStrings.localized("sync.forceDownload.conflictResolved")
                    } else {
                        syncOperationMessage = AppStrings.localized("sync.forceDownload.queued")
                    }
                case .queuedForNextLaunch:
                    syncOperationMessage = AppStrings.localized("sync.forceDownload.queued")
                case .conflictChanged:
                    syncOperationMessage = AppStrings.localized("sync.conflict.error.changed")
                }
            } catch {
                presentSyncRecoveryError(error)
            }
            isCheckingSync = false
        }
    }

    private func presentSyncRecoveryError(_ error: Error) {
        feedbackRouter.present(
            context: .syncRecovery,
            title: AppStrings.localized("settings.syncRecovery.title"),
            message: error.localizedDescription
        )
    }
}
