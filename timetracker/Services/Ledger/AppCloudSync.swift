import Foundation
import OSLog

enum AppCloudSync {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker",
        category: "CloudSync"
    )

    static let containerIdentifier = "iCloud.me.mezorewww.timetracker"
    nonisolated static let enabledKey = "TimeTrackerCloudSyncEnabled"
    static let modeKey = "TimeTrackerPersistenceMode"
    static let errorKey = "TimeTrackerPersistenceError"
    static let accountStatusKey = "TimeTrackerCloudAccountStatus"
    static let pendingCloudUploadResetKey = "TimeTrackerPendingCloudUploadReset"
    static let pendingCloudDownloadResetKey = "TimeTrackerPendingCloudDownloadReset"
    static let queuedCloudReconciliationKey = "TimeTrackerQueuedCloudReconciliation"
    static let activeCloudReconciliationKey = "TimeTrackerActiveCloudReconciliation"
    static let cloudRecoveryStoreResetKey = "TimeTrackerCloudRecoveryStoreReset"
    static let activeCloudDownloadRecoveryKey = "TimeTrackerActiveCloudDownloadRecovery"
    static let modeICloud = "iCloud"
    static let modeLocal = "Local"
    static let modeLocalFallback = "Local fallback"
    static let modeInMemoryFallback = "In-memory fallback"
    static let modeUITest = "UI Test"
    static let modeDemoData = "Demo data"

    static var isEnabled: Bool {
        if AppDefaults.shared.object(forKey: enabledKey) == nil {
            return true
        }
        return AppDefaults.shared.bool(forKey: enabledKey)
    }

    static var persistenceMode: String {
        AppDefaults.shared.string(forKey: modeKey) ?? modeLocal
    }

    static var lastError: String? {
        AppDefaults.shared.string(forKey: errorKey)
    }

    static var persistenceWriteSafety: PersistenceWriteSafety {
        if persistenceMode == modeInMemoryFallback {
            return .ephemeral(lastError)
        }
        if AppDefaults.shared.bool(forKey: pendingCloudDownloadResetKey) ||
            isCloudRecoveryPending
        {
            return .cloudRecoveryPending(lastError)
        }
        return .ready
    }

    static var allowsUserWrites: Bool {
        persistenceWriteSafety == .ready
    }

    static var isCloudRecoveryPending: Bool {
        isCloudReconciliationActive ||
            AppDefaults.shared.bool(forKey: cloudRecoveryStoreResetKey) ||
            isCloudDownloadRecoveryActive
    }

    static var isCloudReconciliationActive: Bool {
        AppDefaults.shared.bool(forKey: activeCloudReconciliationKey)
    }

    static var isCloudDownloadRecoveryActive: Bool {
        AppDefaults.shared.bool(forKey: activeCloudDownloadRecoveryKey)
    }

    static var isCloudImportRecoveryActive: Bool {
        isCloudReconciliationActive || isCloudDownloadRecoveryActive
    }

    /// Permanent tombstone deletion is safe only for stores that cannot later
    /// rejoin CloudKit with an offline device carrying an older visible copy.
    static var allowsPermanentTombstonePurge: Bool {
        switch persistenceMode {
        case modeUITest, modeDemoData:
            true
        case modeICloud, modeLocal, modeLocalFallback, modeInMemoryFallback:
            false
        default:
            false
        }
    }

    /// Local persistent stores can be temporary waypoints while CloudKit is
    /// unavailable or waiting for a restart. Preserve every committed mutation
    /// so the next CloudKit launch can compare both branches before asking the
    /// user which one should win.
    static var shouldStageLocalMutationsForCloudRecovery: Bool {
        guard isEnabled else { return false }
        switch persistenceMode {
        case modeLocal, modeLocalFallback:
            return true
        case modeICloud, modeInMemoryFallback, modeUITest, modeDemoData:
            return false
        default:
            return false
        }
    }

    /// A pending download is an explicit choice to replace the device branch,
    /// so it must not be converted back into a local reconciliation request.
    static var shouldRefreshLocalFallbackRecoverySnapshotBeforeReset: Bool {
        isEnabled &&
            persistenceMode == modeLocalFallback &&
            AppDefaults.shared.bool(forKey: pendingCloudDownloadResetKey) == false
    }

    static func requireUserWritesAllowed() throws {
        guard allowsUserWrites else {
            throw PersistenceWriteError.blocked(persistenceWriteSafety.message)
        }
    }

    static var allowsAutomaticDemoSeeding: Bool {
        guard lastError?.isEmpty ?? true else { return false }
        switch persistenceMode {
        case modeLocal, modeUITest, modeDemoData:
            return true
        default:
            return false
        }
    }

    static func recordCloudKitEnabled(after recovery: CompletedCloudRecovery) {
        let defaults = AppDefaults.shared
        AppDemoDataConfiguration.disableLocalDemoStoreForCloudSync()
        defaults.set(modeICloud, forKey: modeKey)
        defaults.removeObject(forKey: errorKey)
        let activatesReconciliation = defaults.bool(forKey: queuedCloudReconciliationKey)
        if activatesReconciliation {
            defaults.set(true, forKey: activeCloudReconciliationKey)
            defaults.removeObject(forKey: queuedCloudReconciliationKey)
        }
        if recovery.reset == .download {
            defaults.set(true, forKey: activeCloudDownloadRecoveryKey)
        }
        if activatesReconciliation || recovery.reset != .upload {
            defaults.removeObject(forKey: cloudRecoveryStoreResetKey)
        }
        defaults.removeObject(forKey: pendingCloudUploadResetKey)
        defaults.removeObject(forKey: pendingCloudDownloadResetKey)
        logger.info(
            "CloudKit storage is active after completed recovery: \(String(describing: recovery.reset), privacy: .public)"
        )
    }

    static func recordCloudKitDisabledByUser() {
        cancelCloudReconciliation()
        completeCloudDownloadRecovery()
        let defaults = AppDefaults.shared
        defaults.removeObject(forKey: pendingCloudDownloadResetKey)
        defaults.set(modeLocal, forKey: modeKey)
        defaults.removeObject(forKey: errorKey)
        logger.info("CloudKit storage is disabled by user preference")
    }

    static func recordLocalFallback(error: Error) {
        AppDefaults.shared.set(modeLocalFallback, forKey: modeKey)
        AppDefaults.shared.set(error.localizedDescription, forKey: errorKey)
        logger.error("CloudKit storage fell back to local store: \(error.localizedDescription, privacy: .public)")
    }

    static func recordEmergencyInMemoryFallback(error: Error) {
        AppDefaults.shared.set(modeInMemoryFallback, forKey: modeKey)
        AppDefaults.shared.set(
            String(format: AppStrings.localized("sync.temporaryStoreError"), error.localizedDescription),
            forKey: errorKey
        )
        logger.fault("Persistent storage fell back to in-memory store: \(error.localizedDescription, privacy: .public)")
    }

    static func recordUITesting() {
        AppDefaults.shared.set(modeUITest, forKey: modeKey)
        AppDefaults.shared.removeObject(forKey: errorKey)
        AppDefaults.shared.removeObject(forKey: pendingCloudUploadResetKey)
        AppDefaults.shared.removeObject(forKey: pendingCloudDownloadResetKey)
        AppDefaults.shared.removeObject(forKey: queuedCloudReconciliationKey)
        AppDefaults.shared.removeObject(forKey: activeCloudReconciliationKey)
        AppDefaults.shared.removeObject(forKey: cloudRecoveryStoreResetKey)
        AppDefaults.shared.removeObject(forKey: activeCloudDownloadRecoveryKey)
    }

    static func recordDemoDataMode() {
        AppDefaults.shared.set(modeDemoData, forKey: modeKey)
        AppDefaults.shared.removeObject(forKey: errorKey)
    }
}
