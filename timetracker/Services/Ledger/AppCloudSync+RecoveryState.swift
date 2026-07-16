import Foundation

extension AppCloudSync {
    static func activateCloudReconciliation() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: activeCloudReconciliationKey)
        defaults.removeObject(forKey: queuedCloudReconciliationKey)
    }

    static func completeCloudReconciliation() {
        let defaults = UserDefaults.standard
        let hadPendingRecovery = defaults.bool(forKey: queuedCloudReconciliationKey) ||
            defaults.bool(forKey: activeCloudReconciliationKey) ||
            defaults.bool(forKey: cloudRecoveryStoreResetKey)
        defaults.removeObject(forKey: queuedCloudReconciliationKey)
        defaults.removeObject(forKey: activeCloudReconciliationKey)
        defaults.removeObject(forKey: cloudRecoveryStoreResetKey)
        if hadPendingRecovery {
            NotificationCenter.default.post(name: .appCloudRecoveryStateChanged, object: nil)
        }
    }

    static func completeCloudDownloadRecovery() {
        let defaults = UserDefaults.standard
        let wasActive = defaults.bool(forKey: activeCloudDownloadRecoveryKey)
        defaults.removeObject(forKey: activeCloudDownloadRecoveryKey)
        if wasActive {
            NotificationCenter.default.post(name: .appCloudRecoveryStateChanged, object: nil)
        }
    }

    static func cancelCloudReconciliation() {
        let defaults = UserDefaults.standard
        let hadReconciliation = defaults.bool(forKey: queuedCloudReconciliationKey) ||
            defaults.bool(forKey: activeCloudReconciliationKey) ||
            defaults.bool(forKey: cloudRecoveryStoreResetKey)
        completeCloudReconciliation()
        if hadReconciliation {
            defaults.removeObject(forKey: pendingCloudUploadResetKey)
        }
    }
}

extension Notification.Name {
    static let appCloudRecoveryStateChanged = Notification.Name(
        "TimeTrackerAppCloudRecoveryStateChanged"
    )
}
