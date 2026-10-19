import Foundation

nonisolated extension AnalyticsStore {
    func rootBreakdown(
        segments: [AnalyticsSegmentRecord],
        tasks: [AnalyticsTaskRecord],
        sessions: [AnalyticsSessionRecord],
        taskPathByID: [UUID: String],
        interval: DateInterval,
        evaluatedAt cutoff: Date
    ) -> [AnalyticsGroupBreakdownPoint] {
        let taskByID = tasks.latestByID()
        let sessionsByTaskID = Dictionary(grouping: sessions.deduplicatedByID(), by: \.taskID)
        let bounded = boundedSegments(segments, in: interval, now: cutoff)
        let grouped = Dictionary(grouping: bounded) { item -> String in
            guard let task = taskByID[item.segment.taskID],
                  let root = rootTask(for: task, taskByID: taskByID)
            else {
                return "deleted-\(item.segment.taskID.uuidString)"
            }
            return root.id.uuidString
        }

        return grouped.compactMap { groupID, items -> AnalyticsGroupBreakdownPoint? in
            guard let first = items.first else { return nil }
            let task = taskByID[first.segment.taskID]
            let root = task.flatMap { rootTask(for: $0, taskByID: taskByID) }
            let title = root?.title
                ?? sessionsByTaskID[first.segment.taskID]?.first?.titleSnapshot
                ?? AppStrings.localized("task.unavailable")
            let path = root.flatMap { taskPathByID[$0.id] }
                ?? AppStrings.localized("task.unavailable.path")
            return groupPoint(
                id: "root-\(groupID)",
                kind: .rootTask,
                title: title,
                subtitle: path,
                iconName: root?.iconName ?? "checkmark.circle",
                colorHex: root?.colorHex ?? "0A84FF",
                items: items
            )
        }
        .sorted { $0.grossSeconds > $1.grossSeconds }
    }

    func categoryBreakdown(
        segments: [AnalyticsSegmentRecord],
        tasks: [AnalyticsTaskRecord],
        taskCategories: [AnalyticsCategoryRecord],
        categoryIDByRootTaskID: [UUID: UUID],
        interval: DateInterval,
        evaluatedAt cutoff: Date
    ) -> [AnalyticsGroupBreakdownPoint] {
        let taskByID = tasks.latestByID()
        let categoryByID = taskCategories.visibleDeduplicatedByID().latestByID()
        let bounded = boundedSegments(segments, in: interval, now: cutoff)
        let grouped = Dictionary(grouping: bounded) { item -> String in
            guard let task = taskByID[item.segment.taskID],
                  let root = rootTask(for: task, taskByID: taskByID),
                  let categoryID = categoryIDByRootTaskID[root.id],
                  categoryByID[categoryID] != nil
            else {
                return "uncategorized"
            }
            return categoryID.uuidString
        }

        return grouped.compactMap { groupID, items -> AnalyticsGroupBreakdownPoint? in
            guard !items.isEmpty else { return nil }
            let category = UUID(uuidString: groupID).flatMap { categoryByID[$0] }
            return groupPoint(
                id: "category-\(groupID)",
                kind: .category,
                title: category?.title ?? AppStrings.localized("taskCategory.uncategorized"),
                subtitle: AppStrings.localized("analytics.group.category"),
                iconName: category?.iconName ?? "tray",
                colorHex: category?.colorHex ?? "8E8E93",
                items: items
            )
        }
        .sorted { $0.grossSeconds > $1.grossSeconds }
    }

    func groupPoint(
        id: String,
        kind: AnalyticsGroupBreakdownPoint.GroupKind,
        title: String,
        subtitle: String,
        iconName: String,
        colorHex: String,
        items: [AnalyticsBoundedSegment]
    ) -> AnalyticsGroupBreakdownPoint {
        let gross = items.reduce(0) { $0 + $1.durationSeconds }
        let wall = TimeAggregationService.mergeOverlappingIntervals(items.map(\.interval)).reduce(0) {
            $0 + Int($1.end.timeIntervalSince($1.start))
        }
        return AnalyticsGroupBreakdownPoint(
            id: id,
            kind: kind,
            title: title,
            subtitle: subtitle,
            iconName: iconName,
            colorHex: colorHex,
            grossSeconds: gross,
            wallSeconds: wall
        )
    }

    func rootTask(for task: AnalyticsTaskRecord, taskByID: [UUID: AnalyticsTaskRecord]) -> AnalyticsTaskRecord? {
        var cursor = task
        var visited: Set<UUID> = [task.id]
        while let parentID = cursor.parentID,
              !visited.contains(parentID),
              let parent = taskByID[parentID],
              parent.deletedAt == nil
        {
            visited.insert(parentID)
            cursor = parent
        }
        return cursor
    }
}
