import Foundation

struct PreferenceStore {
    private(set) var syncedPreferences: [SyncedPreference] = []
    private(set) var preferences = AppPreferences.defaults

    mutating func refresh(syncedPreferences: [SyncedPreference]) {
        self.syncedPreferences = syncedPreferences
        preferences = AppPreferences(syncedPreferences: syncedPreferences)
        SyncedPreferenceService.syncLocalMirrors(preferences)
    }
}
