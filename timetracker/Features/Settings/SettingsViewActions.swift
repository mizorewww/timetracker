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
        Task {
            await store.refreshCloudAccountStatus()
            syncCheckMessage = store.syncStatus.accountStatus
            isCheckingSync = false
        }
    }

    func forceSyncRefresh() {
        isCheckingSync = true
        Task {
            syncCheckMessage = await store.forceCloudSyncRefresh()
            isCheckingSync = false
        }
    }

    func forceDownloadCloudData() {
        isCheckingSync = true
        Task {
            if store.pendingSyncConflict != nil {
                store.resolveSyncConflict(.downloadCloud)
                if store.pendingSyncConflict == nil {
                    syncCheckMessage = AppStrings.localized("sync.forceDownload.conflictResolved")
                }
            } else if store.acceptCurrentCloudData() != nil {
                syncCheckMessage = AppStrings.localized("sync.forceDownload.queued")
            }
            isCheckingSync = false
        }
    }

    var syncCheckPresented: Binding<Bool> {
        Binding {
            syncCheckMessage != nil
        } set: { isPresented in
            if !isPresented {
                syncCheckMessage = nil
            }
        }
    }

    var optimizationMessagePresented: Binding<Bool> {
        Binding {
            databaseOptimizationMessage != nil
        } set: { isPresented in
            if !isPresented {
                databaseOptimizationMessage = nil
            }
        }
    }
}
