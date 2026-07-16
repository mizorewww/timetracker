import SwiftUI

extension SettingsView {
    var hasDemoData: Bool {
        store.tasks.contains { $0.deviceID == "demo" } ||
            store.allSegments.contains { $0.deviceID == "demo" } ||
            store.pomodoroRuns.contains { $0.deviceID == "demo" } ||
            store.countdownEvents.contains { $0.deviceID == "demo" } ||
            store.checklistItems.contains { $0.deviceID == "demo" } ||
            store.inboxItems.contains { $0.deviceID == "demo" }
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
            lastRefreshAt: store.lastSyncRefreshAt
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
        let result = store.resolveSyncConflict(
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
        case .conflictChanged, .failed:
            break
        }
    }

    func forceDownloadCloudData(expectedConflictID: UUID?) {
        isCheckingSync = true
        Task {
            let result = store.resolveSyncConflict(
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
            case .conflictChanged, .failed:
                break
            }
            isCheckingSync = false
        }
    }

}
