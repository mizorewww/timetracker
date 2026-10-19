import Foundation
import SwiftData

extension TimeTrackerStore {
    func setAllowParallelTimers(_ value: Bool) throws {
        try setPreference(.allowParallelTimers, valueJSON: PreferenceJSON.encode(value))
    }

    func setShowGrossAndWallTogether(_ value: Bool) throws {
        try setPreference(.showGrossAndWallTogether, valueJSON: PreferenceJSON.encode(value))
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
}
