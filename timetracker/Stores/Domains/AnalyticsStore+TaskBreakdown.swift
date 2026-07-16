import Foundation

extension AnalyticsStore {
    func taskBreakdown(
        items: [AnalyticsBoundedSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        taskPathByID: [UUID: String]
    ) -> [TaskAnalyticsPoint] {
        let taskByID = tasks.latestByID()
        let fallbackTitleByTaskID = AnalyticsSelectionPolicy.latestSessionTitleByTaskID(
            sessions: sessions
        )
        let grouped = Dictionary(grouping: items) { $0.segment.taskID }
        let points = grouped.compactMap { taskID, taskItems -> TaskAnalyticsPoint? in
            let gross = taskItems.reduce(0) { $0 + $1.durationSeconds }
            guard gross > 0 else { return nil }

            let task = taskByID[taskID]
            return TaskAnalyticsPoint(
                taskID: taskID,
                title: task?.title
                    ?? fallbackTitleByTaskID[taskID]
                    ?? AppStrings.localized("task.deleted"),
                path: task.map {
                    taskPathByID[$0.id] ?? $0.title
                } ?? AppStrings.localized("task.deleted.path"),
                colorHex: task?.colorHex,
                iconName: task?.iconName,
                status: task?.status,
                grossSeconds: gross,
                wallSeconds: TimeAggregationService()
                    .mergeOverlappingIntervals(taskItems.map(\.interval))
                    .reduce(0) {
                        $0 + Int($1.end.timeIntervalSince($1.start))
                    }
            )
        }
        return AnalyticsSelectionPolicy.rankedTasks(points)
    }
}
