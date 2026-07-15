import Foundation

struct PreferenceStore {
    private(set) var syncedPreferences: [SyncedPreference] = []
    private(set) var preferences = AppPreferences.defaults

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
