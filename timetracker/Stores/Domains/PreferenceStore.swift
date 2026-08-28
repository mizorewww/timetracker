import Foundation

struct PreferenceStore {
    private(set) var syncedPreferences: [SyncedPreference] = []
    /// Settable so the facade's computed `preferences` passthrough can forward
    /// the device-local optimistic mutations from preference commands.
    var preferences = AppPreferences.defaults

    mutating func refresh(
        syncedPreferences: [SyncedPreference],
        localLLMAPIKey: String,
        localLLMAutomaticSuggestionsEnabled: Bool
    ) {
        self.syncedPreferences = syncedPreferences
        preferences = AppPreferences(syncedPreferences: syncedPreferences)
        preferences.llmAPIKey = localLLMAPIKey
        preferences.llmAutomaticSuggestionsEnabled = localLLMAutomaticSuggestionsEnabled
    }
}
