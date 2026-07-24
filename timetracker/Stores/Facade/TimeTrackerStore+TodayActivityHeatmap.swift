import Foundation

extension TimeTrackerStore {
    var todayHeatmapSelectedTaskIDs: [UUID] {
        _ = taskReadModelRevision
        return todayHeatmapRecurrenceProjection.canonicalTaskIDs(
            preferences.todayHeatmapTaskIDs
        )
    }

    var todayHeatmapRenderableTaskIDs: [UUID] {
        _ = taskReadModelRevision
        return todayHeatmapRecurrenceProjection.renderableTaskIDs(
            preferences.todayHeatmapTaskIDs
        )
    }

    var todayHeatmapSelectableTaskIDs: Set<UUID> {
        _ = taskReadModelRevision
        return todayHeatmapRecurrenceProjection.selectableTaskIDs(
            from: parentEligibleTaskIDs
        )
    }

    func todayHeatmapOwnerTaskID(for taskID: UUID) -> UUID? {
        _ = taskReadModelRevision
        let ownerTaskID = todayHeatmapRecurrenceProjection.ownerTaskID(
            for: taskID
        )
        return todayHeatmapRecurrenceProjection.renderableTaskIDs([
            ownerTaskID
        ]).first
    }

    func todayTaskActivityHeatmapSnapshots(
        period: ActivityHeatmapPeriod,
        now: Date,
        calendar: Calendar = .current
    ) async -> [TaskActivityHeatmapSnapshot] {
        await TodayActivityHeatmapSnapshotService().taskSnapshots(
            selectedTaskIDs: todayHeatmapRenderableTaskIDs,
            taskByID: taskByID,
            childrenByParentID: childrenByParentID,
            additionalContributingTaskIDsBySelectedTaskID:
                todayHeatmapRecurrenceProjection
                    .generatedTaskIDsByTemplateTaskID,
            segments: allSegments,
            checklistItems: checklistItems,
            quantityGoals: taskQuantityGoals,
            quantityEntries: taskQuantityEntries,
            period: period,
            now: now,
            calendar: calendar
        )
    }

}
