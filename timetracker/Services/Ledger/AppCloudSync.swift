import CloudKit
import Foundation
import OSLog
import SwiftData

/// Device-local CloudKit configuration and the persistence mode the current
/// launch actually opened. CloudKit mirroring syncs and merges records; reads
/// resolve duplicates with the deterministic LWW order (AD-014).
enum AppCloudSync {
    static let logger = Logger(
        subsystem: AppIdentity.loggingSubsystem,
        category: "CloudSync"
    )

    nonisolated static let containerIdentifier =
        "iCloud.me.mezorewww.timetracker"
    nonisolated static let enabledKey = "TimeTrackerCloudSyncEnabled"
    nonisolated static let modeKey = "TimeTrackerPersistenceMode"
    nonisolated static let errorKey = "TimeTrackerPersistenceError"
    nonisolated static let modeICloud = "iCloud"
    nonisolated static let modeLocal = "Local"
    nonisolated static let modeLocalFallback = "Local fallback"
    nonisolated static let modeInMemoryFallback =
        "In-memory fallback"
    nonisolated static let modeUITest = "UI Test"
    nonisolated static let modeDemoData = "Demo data"

    static var persistentStoreURL: URL {
        ModelConfiguration(
            "TimeTracker",
            schema: nil,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        ).url
    }

    /// Takes effect on the next launch.
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
        persistenceMode == modeInMemoryFallback ? .ephemeral(lastError) : .ready
    }

    static var allowsUserWrites: Bool {
        persistenceWriteSafety == .ready
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

    static func setEnabled(_ isEnabled: Bool) {
        #if DEBUG
        if isEnabled {
            SeedData.setAutomaticDemoSeedingDisabled(true)
        }
        #endif
        AppDefaults.shared.set(isEnabled, forKey: enabledKey)
    }

    static func recordMode(_ mode: String, error: String? = nil) {
        AppDefaults.shared.set(mode, forKey: modeKey)
        if let error {
            AppDefaults.shared.set(error, forKey: errorKey)
        } else {
            AppDefaults.shared.removeObject(forKey: errorKey)
        }
    }

    static func recordLocalFallback(error: Error) {
        recordMode(modeLocalFallback, error: error.localizedDescription)
        logger.error("CloudKit storage fell back to local store: \(error.localizedDescription, privacy: .public)")
    }

    static func recordEmergencyInMemoryFallback(error: Error) {
        recordMode(
            modeInMemoryFallback,
            error: String(format: AppStrings.localized("sync.temporaryStoreError"), error.localizedDescription)
        )
        logger.fault("Persistent storage fell back to in-memory store: \(error.localizedDescription, privacy: .public)")
    }

    static func checkAccountStatus(
        client: CloudAccountStatusClient? = nil,
        checkedAt: Date = Date()
    ) async -> CloudAccountCheckOutcome {
        let resolvedClient = client ?? .live(containerIdentifier: containerIdentifier)
        let result: CloudAccountCheckResult
        do {
            switch try await resolvedClient.fetchStatus() {
            case .available:
                result = .available
            case .noAccount:
                result = .unavailable(.noAccount)
            case .restricted:
                result = .unavailable(.restricted)
            case .couldNotDetermine:
                result = .unavailable(.couldNotDetermine)
            case .temporarilyUnavailable:
                result = .unavailable(.temporarilyUnavailable)
            @unknown default:
                result = .unavailable(.unknown)
            }
        } catch {
            result = .failed(message: error.localizedDescription)
        }
        logger.info("CloudKit account check completed: \(String(describing: result), privacy: .public)")
        return CloudAccountCheckOutcome(checkedAt: checkedAt, result: result)
    }
}
