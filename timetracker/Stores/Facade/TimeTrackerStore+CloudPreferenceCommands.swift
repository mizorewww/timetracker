import Foundation

extension TimeTrackerStore {
    @discardableResult
    func setCloudSyncEnabled(_ value: Bool) -> Bool {
        guard value != preferences.cloudSyncEnabled else { return true }
        if !value {
            AppCloudSync.cancelCloudReconciliation()
            UserDefaults.standard.set(false, forKey: AppCloudSync.enabledKey)
            preferences.cloudSyncEnabled = false
            return true
        }

        do {
            try writeAuthorization.requireUserWritesAllowed()
            guard let modelContext else { throw StoreError.notConfigured }
            if AppCloudSync.persistenceMode != AppCloudSync.modeICloud {
                _ = try syncConflictService.stageCurrentLocalSnapshotForCloudEnablement(
                    context: modelContext
                )
            }
            UserDefaults.standard.set(true, forKey: AppCloudSync.enabledKey)
            preferences.cloudSyncEnabled = true
            return true
        } catch {
            UserDefaults.standard.set(false, forKey: AppCloudSync.enabledKey)
            preferences.cloudSyncEnabled = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func setQuickStartTaskIDs(_ ids: [UUID]) -> Bool {
        let normalized = AppPreferenceValueSanitizer.quickStartTaskIDs(ids)
        return setPreference(
            .quickStartTaskIDs,
            valueJSON: PreferenceJSON.encode(normalized.map(\.uuidString))
        )
    }
}
