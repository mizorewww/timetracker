import Foundation
import OSLog

enum AppCloudSync {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker",
        category: "CloudSync"
    )

    static let containerIdentifier = "iCloud.me.mezorewww.timetracker"
    static let enabledKey = "TimeTrackerCloudSyncEnabled"
    static let modeKey = "TimeTrackerPersistenceMode"
    static let errorKey = "TimeTrackerPersistenceError"
    static let accountStatusKey = "TimeTrackerCloudAccountStatus"
    static let pendingCloudUploadResetKey = "TimeTrackerPendingCloudUploadReset"
    static let pendingCloudDownloadResetKey = "TimeTrackerPendingCloudDownloadReset"
    static let modeICloud = "iCloud"
    static let modeLocal = "Local"
    static let modeLocalFallback = "Local fallback"
    static let modeInMemoryFallback = "In-memory fallback"
    static let modeUITest = "UI Test"
    static let modeDemoData = "Demo data"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: enabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var persistenceMode: String {
        UserDefaults.standard.string(forKey: modeKey) ?? modeLocal
    }

    static var lastError: String? {
        UserDefaults.standard.string(forKey: errorKey)
    }

    static var persistenceWriteSafety: PersistenceWriteSafety {
        if persistenceMode == modeInMemoryFallback {
            return .ephemeral(lastError)
        }
        if UserDefaults.standard.bool(forKey: pendingCloudDownloadResetKey) {
            return .cloudRecoveryPending(lastError)
        }
        return .ready
    }

    static var allowsUserWrites: Bool {
        persistenceWriteSafety == .ready
    }

    /// Permanent tombstone deletion is safe only for stores that cannot later
    /// rejoin CloudKit with an offline device carrying an older visible copy.
    static var allowsPermanentTombstonePurge: Bool {
        switch persistenceMode {
        case modeUITest, modeDemoData:
            return true
        case modeICloud, modeLocal, modeLocalFallback, modeInMemoryFallback:
            return false
        default:
            return false
        }
    }

    /// Local persistent stores can be temporary waypoints while CloudKit is
    /// unavailable or waiting for a restart. Preserve every committed mutation
    /// so the next CloudKit launch can rebuild from the local winner instead of
    /// silently accepting an older remote snapshot.
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
        AppDemoDataConfiguration.disableLocalDemoStoreForCloudSync()
        UserDefaults.standard.set(modeICloud, forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
        UserDefaults.standard.removeObject(forKey: pendingCloudUploadResetKey)
        UserDefaults.standard.removeObject(forKey: pendingCloudDownloadResetKey)
        logger.info(
            "CloudKit storage is active after completed recovery: \(String(describing: recovery.reset), privacy: .public)"
        )
    }

    static func recordCloudKitDisabledByUser() {
        UserDefaults.standard.set(modeLocal, forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
        logger.info("CloudKit storage is disabled by user preference")
    }

    static func recordLocalFallback(error: Error) {
        UserDefaults.standard.set(modeLocalFallback, forKey: modeKey)
        UserDefaults.standard.set(error.localizedDescription, forKey: errorKey)
        logger.error("CloudKit storage fell back to local store: \(error.localizedDescription, privacy: .public)")
    }

    static func recordEmergencyInMemoryFallback(error: Error) {
        UserDefaults.standard.set(modeInMemoryFallback, forKey: modeKey)
        UserDefaults.standard.set(
            String(format: AppStrings.localized("sync.temporaryStoreError"), error.localizedDescription),
            forKey: errorKey
        )
        logger.fault("Persistent storage fell back to in-memory store: \(error.localizedDescription, privacy: .public)")
    }

    static func recordUITesting() {
        UserDefaults.standard.set(modeUITest, forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
        UserDefaults.standard.removeObject(forKey: pendingCloudUploadResetKey)
        UserDefaults.standard.removeObject(forKey: pendingCloudDownloadResetKey)
    }

    static func recordDemoDataMode() {
        UserDefaults.standard.set(modeDemoData, forKey: modeKey)
        UserDefaults.standard.removeObject(forKey: errorKey)
    }

}

/// Selects the write-safety authority used by a store facade.
///
/// Production stores always use `applicationState`. Unit tests opt into the
/// isolated harness explicitly so a developer's real fallback/recovery state
/// cannot make an in-memory fixture read-only or be changed by the test.
enum StoreWriteAuthorization {
    case applicationState
    case isolatedTestHarness

    func requireUserWritesAllowed() throws {
        switch self {
        case .applicationState:
            try AppCloudSync.requireUserWritesAllowed()
        case .isolatedTestHarness:
            return
        }
    }
}
