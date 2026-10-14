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
