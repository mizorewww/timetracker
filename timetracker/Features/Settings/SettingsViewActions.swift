import SwiftUI

extension SettingsView {
    #if DEBUG
    /// Surfaces the cleanup action whenever any synthetic row is present.
    var hasDemoData: Bool {
        store.tasks.contains { SyntheticDataOrigin.marks($0.deviceID) } ||
            store.allSegments.contains { SyntheticDataOrigin.marks($0.deviceID) } ||
            store.pomodoroRuns.contains { SyntheticDataOrigin.marks($0.deviceID) } ||
            store.countdownEvents.contains { SyntheticDataOrigin.marks($0.deviceID) } ||
            store.checklistItems.contains { SyntheticDataOrigin.marks($0.deviceID) } ||
            store.inboxItems.contains { SyntheticDataOrigin.marks($0.deviceID) }
    }
    #endif

    var currentStorageValue: String {
        store.preferences.cloudSyncEnabled
            ? (store.syncStatus.isCloudBacked ? "iCloud" : AppStrings.localized("settings.localWillRetryCloud"))
            : AppStrings.localized("settings.local")
    }

    var syncFeedback: SyncFeedback {
        store.syncStatus.feedback(
            preferences: store.preferences,
            isChecking: isCheckingSync,
            activity: store.lastSyncActivity
        )
    }

    func checkSyncStatus() {
        isCheckingSync = true
        Task {
            _ = await store.refreshCloudAccountStatus()
            isCheckingSync = false
        }
    }
}
