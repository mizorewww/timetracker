import Foundation

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
        perform(event: .preferenceChanged(key: key.rawValue)) {
            guard let modelContext else { throw StoreError.notConfigured }
            try preferenceCommandHandler.set(key: key, valueJSON: valueJSON, context: modelContext)
        }
    }
}
