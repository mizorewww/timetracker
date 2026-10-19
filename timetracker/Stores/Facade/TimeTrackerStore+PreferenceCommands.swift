import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func setAllowParallelTimers(_ value: Bool) -> Bool {
        setPreference(.allowParallelTimers, valueJSON: PreferenceJSON.encode(value))
    }

    @discardableResult
    func setShowGrossAndWallTogether(_ value: Bool) -> Bool {
        setPreference(.showGrossAndWallTogether, valueJSON: PreferenceJSON.encode(value))
    }

    @discardableResult
    func setPreference(_ key: AppPreferenceKey, valueJSON: String) -> Bool {
        performStoreCommand(
            eventsForOutcome: { _ in [.preferenceChanged(key: key.rawValue)] }
        ) { session in
            try StoreScopedPreferenceCommandCoordinator(
                session: session
            ).set(key: key, valueJSON: valueJSON)
        } != nil
    }
}
