import Foundation

extension TimeTrackerStore {
    func setPreferredColorScheme(_ value: String) {
        setPreference(.preferredColorScheme, valueJSON: PreferenceJSON.encode(value))
    }

    func setPomodoroDefaultMode(_ value: String) {
        setPreference(.pomodoroDefaultMode, valueJSON: PreferenceJSON.encode(value))
    }

    func setDefaultFocusMinutes(_ value: Int) {
        setPreference(.defaultFocusMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...480)))
    }

    func setDefaultBreakMinutes(_ value: Int) {
        setPreference(.defaultBreakMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...480)))
    }

    func setDefaultPomodoroRounds(_ value: Int) {
        setPreference(.defaultPomodoroRounds, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...24)))
    }

    func setAllowParallelTimers(_ value: Bool) {
        setPreference(.allowParallelTimers, valueJSON: PreferenceJSON.encode(value))
    }

    func setShowGrossAndWallTogether(_ value: Bool) {
        setPreference(.showGrossAndWallTogether, valueJSON: PreferenceJSON.encode(value))
    }

    func setCloudSyncEnabled(_ value: Bool) {
        setPreference(.cloudSyncEnabled, valueJSON: PreferenceJSON.encode(value))
        UserDefaults.standard.set(value, forKey: AppCloudSync.enabledKey)
    }

    func setQuickStartTaskIDs(_ ids: [UUID]) {
        setPreference(.quickStartTaskIDs, valueJSON: PreferenceJSON.encode(ids.map(\.uuidString)))
    }

    private func setPreference(_ key: AppPreferenceKey, valueJSON: String) {
        perform(event: .preferenceChanged(key: key.rawValue)) {
            guard let modelContext else { throw StoreError.notConfigured }
            try preferenceCommandHandler.set(key: key, valueJSON: valueJSON, context: modelContext)
        }
    }
}
