import Foundation
import SwiftData

extension TimeTrackerStore {
    func setAllowParallelTimers(_ value: Bool) throws {
        try setPreference(.allowParallelTimers, valueJSON: PreferenceJSON.encode(value))
    }

    func setShowGrossAndWallTogether(_ value: Bool) throws {
        try setPreference(.showGrossAndWallTogether, valueJSON: PreferenceJSON.encode(value))
    }

    func setPomodoroPlans(_ plans: [PomodoroPlan]) throws {
        try setPreference(
            .pomodoroPlans,
            valueJSON: PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroPlans(plans))
        )
    }

    func setPreference(_ key: AppPreferenceKey, valueJSON: String) throws {
        try performStoreCommand(
            eventsForOutcome: { _ in [.preferenceChanged(key: key.rawValue)] }
        ) { session in
            try StoreScopedPreferenceCommandCoordinator(
                session: session
            ).set(key: key, valueJSON: valueJSON)
        }
    }

    var syncStatus: SyncStatus {
        SyncStatus(
            mode: AppCloudSync.persistenceMode,
            containerIdentifier: AppCloudSync.containerIdentifier,
            deviceID: DeviceIdentity.current,
            lastError: AppCloudSync.lastError,
            accountCheck: cloudAccountCheck
        )
    }
}
