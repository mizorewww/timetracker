import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func setPreferredColorScheme(_ value: String) -> Bool {
        setPreference(
            .preferredColorScheme,
            valueJSON: PreferenceJSON.encode(AppPreferenceValueSanitizer.preferredColorScheme(value))
        )
    }

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
        guard let modelContext else {
            errorMessage = StoreError.notConfigured.localizedDescription
            return false
        }
        do {
            try StoreScopedPreferenceCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).set(key: key, valueJSON: valueJSON)
            finishStoreScopedMutation(events: [.preferenceChanged(key: key.rawValue)])
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
