import Foundation

extension TimeTrackerStore {
    /// Device-local and applied on the next launch. Turning iCloud on keeps
    /// the same store file; CloudKit mirroring exports its existing records.
    func setCloudSyncEnabled(_ value: Bool) {
        guard value != preferences.cloudSyncEnabled else { return }
        AppCloudSync.setEnabled(value)
        preferences.cloudSyncEnabled = value
    }

    func setQuickStartTaskIDs(_ ids: [UUID]) throws {
        let normalized = AppPreferenceValueSanitizer.quickStartTaskIDs(ids)
        try setPreference(
            .quickStartTaskIDs,
            valueJSON: PreferenceJSON.encode(normalized.map(\.uuidString))
        )
    }

    func setTodayHeatmapTaskIDs(_ ids: [UUID]) throws {
        let normalized = AppPreferenceValueSanitizer.todayHeatmapTaskIDs(
            todayHeatmapRecurrenceProjection.canonicalTaskIDs(ids)
        )
        try setPreference(
            .todayHeatmapTaskIDs,
            valueJSON: PreferenceJSON.encode(normalized.map(\.uuidString))
        )
    }

    func setTodayHeatmapPeriod(_ period: ActivityHeatmapPeriod) throws {
        try setPreference(
            .todayHeatmapPeriod,
            valueJSON: PreferenceJSON.encode(period.rawValue)
        )
    }

    @discardableResult
    func setTodayHeatmapTrackingEnabled(
        _ isEnabled: Bool,
        for taskID: UUID
    ) throws -> Bool {
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
        try setTodayHeatmapTaskIDs(updated)
        return true
    }
}
