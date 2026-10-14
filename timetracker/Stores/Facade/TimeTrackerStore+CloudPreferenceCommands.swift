import Foundation

extension TimeTrackerStore {
    /// Device-local and applied on the next launch. Turning iCloud on keeps
    /// the same store file; CloudKit mirroring exports its existing records.
    func setCloudSyncEnabled(_ value: Bool) {
        guard value != preferences.cloudSyncEnabled else { return }
        AppCloudSync.setEnabled(value)
        preferences.cloudSyncEnabled = value
    }

    @discardableResult
    func setQuickStartTaskIDs(_ ids: [UUID]) -> Bool {
        let normalized = AppPreferenceValueSanitizer.quickStartTaskIDs(ids)
        return setPreference(
            .quickStartTaskIDs,
            valueJSON: PreferenceJSON.encode(normalized.map(\.uuidString))
        )
    }

    @discardableResult
    func setTodayHeatmapTaskIDs(_ ids: [UUID]) -> Bool {
        let normalized = AppPreferenceValueSanitizer.todayHeatmapTaskIDs(
            todayHeatmapRecurrenceProjection.canonicalTaskIDs(ids)
        )
        return setPreference(
            .todayHeatmapTaskIDs,
            valueJSON: PreferenceJSON.encode(normalized.map(\.uuidString))
        )
    }

    @discardableResult
    func setTodayHeatmapPeriod(_ period: ActivityHeatmapPeriod) -> Bool {
        setPreference(
            .todayHeatmapPeriod,
            valueJSON: PreferenceJSON.encode(period.rawValue)
        )
    }

    @discardableResult
    func setTodayHeatmapTrackingEnabled(
        _ isEnabled: Bool,
        for taskID: UUID
    ) -> Bool {
        guard let ownerTaskID = todayHeatmapOwnerTaskID(for: taskID) else {
            return false
        }
        let current = todayHeatmapSelectedTaskIDs
        let updated = isEnabled
            ? OrderedTaskIDSelectionMutation.adding(
                ownerTaskID,
                to: current
            )
            : OrderedTaskIDSelectionMutation.removing(
                ownerTaskID,
                from: current
            )
        guard !isEnabled || updated.count <=
            AppPreferenceValueSanitizer.maximumTodayHeatmapTaskCount
        else {
            return false
        }
        return setTodayHeatmapTaskIDs(updated)
    }
}
