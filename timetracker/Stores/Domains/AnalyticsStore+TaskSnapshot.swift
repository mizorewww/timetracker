import Foundation

extension AnalyticsStore {
    func taskSnapshot(
        range: AnalyticsRange,
        task: TaskNode,
        taskIDs: Set<UUID>,
        tasks: [TaskNode],
        segments: [TimeSegment],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        now: Date,
        calendar: Calendar = .current
    ) -> TaskAnalyticsSnapshot {
        let interval = analyticsInterval(for: range, now: now, calendar: calendar)
            ?? DateInterval(start: .distantPast, end: now)
        let canonicalSegments = segments.deduplicatedByID()
        let filtered = canonicalSegments.filter {
            taskIDs.contains($0.taskID) && segmentOverlaps($0, interval: interval, now: now)
        }
        let bounded = boundedSegments(filtered, in: interval, taskIDs: taskIDs, now: now)
        let overview = overview(items: bounded)
        let comparison = comparison(
            segments: canonicalSegments,
            range: range,
            taskIDs: taskIDs,
            now: now,
            calendar: calendar
        )
        let rhythm = rhythm(
            segments: filtered,
            interval: interval,
            taskIDs: taskIDs,
            now: now,
            calendar: calendar
        )
        let quality = quality(
            segments: filtered,
            interval: interval,
            taskIDs: taskIDs,
            now: now
        )
        let dailySummaryService = DailySummaryService()
        let summaries = dailySummaryService.summaries(
            segments: filtered,
            interval: interval,
            now: now,
            calendar: calendar
        )
        let daily = dailySummaryService.visibleSummaries(
            summaries,
            interval: interval,
            evaluatedAt: now
        ).map { summary in
            DailyAnalyticsPoint(
                date: summary.date,
                grossSeconds: summary.grossSeconds,
                wallSeconds: summary.wallClockSeconds,
                label: taskDayLabel(for: summary.date, range: range, calendar: calendar)
            )
        }

        return TaskAnalyticsSnapshot(
            taskID: task.id,
            range: range,
            overview: overview,
            comparison: comparison,
            rhythm: rhythm,
            quality: quality,
            directSeconds: seconds(
                in: interval,
                segments: filtered,
                taskIDs: [task.id],
                mode: .gross,
                now: now
            ),
            descendantSeconds: seconds(
                in: interval,
                segments: filtered,
                taskIDs: taskIDs.subtracting([task.id]),
                mode: .gross,
                now: now
            ),
            childBreakdown: taskChildBreakdown(
                task: task,
                taskIDs: taskIDs,
                tasks: tasks,
                segments: filtered,
                interval: interval,
                now: now
            ),
            daily: daily,
            recentRecords: recentRecords(
                segments: canonicalSegments,
                sessions: sessions,
                tasks: tasks,
                taskIDs: taskIDs,
                taskPathByID: taskPathByID,
                now: now
            )
        )
    }

    func taskAndDescendantIDs(
        for rootTaskID: UUID,
        childrenByParentID: [UUID?: [TaskNode]]
    ) -> Set<UUID> {
        var result = Set<UUID>()
        var pending = [rootTaskID]

        while let taskID = pending.popLast() {
            guard result.insert(taskID).inserted else { continue }
            pending.append(contentsOf: (childrenByParentID[taskID] ?? []).map(\.id))
        }

        return result
    }

    func taskChildBreakdown(
        task: TaskNode,
        taskIDs: Set<UUID>,
        tasks: [TaskNode],
        segments: [TimeSegment],
        interval: DateInterval,
        now: Date
    ) -> [AnalyticsGroupBreakdownPoint] {
        let childrenByParentID = Dictionary(grouping: tasks.filter { $0.deletedAt == nil }, by: \.parentID)
        let boundedByTaskID = Dictionary(
            grouping: boundedSegments(segments, in: interval, taskIDs: taskIDs, now: now),
            by: { $0.segment.taskID }
        )
        var points: [AnalyticsGroupBreakdownPoint] = []
        let directItems = boundedByTaskID[task.id] ?? []
        if !directItems.isEmpty {
            points.append(
                groupPoint(
                    id: "task-\(task.id.uuidString)-direct",
                    kind: .rootTask,
                    title: task.title,
                    subtitle: AppStrings.localized("task.detail.directTime"),
                    iconName: task.iconName ?? "checkmark.circle",
                    colorHex: task.colorHex ?? "0A84FF",
                    items: directItems
                )
            )
        }

        for child in childrenByParentID[task.id] ?? [] {
            let childIDs = taskAndDescendantIDs(
                for: child.id,
                childrenByParentID: childrenByParentID
            ).intersection(taskIDs)
            let items = childIDs.flatMap { boundedByTaskID[$0] ?? [] }
            guard !items.isEmpty else { continue }
            points.append(
                groupPoint(
                    id: "task-\(child.id.uuidString)",
                    kind: .rootTask,
                    title: child.title,
                    subtitle: AppStrings.localized("task.detail.childBranch"),
                    iconName: child.iconName ?? "checkmark.circle",
                    colorHex: child.colorHex ?? "0A84FF",
                    items: items
                )
            )
        }

        return points.sorted { $0.grossSeconds > $1.grossSeconds }
    }

    func recentRecords(
        segments: [TimeSegment],
        sessions: [TimeSession],
        tasks: [TaskNode],
        taskIDs: Set<UUID>,
        taskPathByID: [UUID: String],
        now: Date
    ) -> [TaskRecentRecordPoint] {
        let taskByID = tasks.latestByID()
        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.deduplicatedByID().map { ($0.id, $0) })
        return segments.deduplicatedByID()
            .filter { taskIDs.contains($0.taskID) && $0.deletedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(8)
            .map { segment in
                let task = taskByID[segment.taskID]
                return TaskRecentRecordPoint(
                    id: segment.id,
                    taskID: segment.taskID,
                    title: task?.title
                        ?? sessionByID[segment.sessionID]?.titleSnapshot
                        ?? AppStrings.localized("task.deleted"),
                    path: task.flatMap { taskPathByID[$0.id] }
                        ?? AppStrings.localized("task.deleted.path"),
                    startedAt: segment.startedAt,
                    endedAt: segment.endedAt,
                    durationSeconds: TrackedTimePolicy.elapsedSeconds(
                        startedAt: segment.startedAt,
                        endedAt: segment.endedAt,
                        now: now
                    )
                )
            }
    }

    func taskDayLabel(for date: Date, range: AnalyticsRange, calendar: Calendar) -> String {
        switch range {
        case .today:
            return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        case .week:
            let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
            return "\(weekday) \(calendar.component(.day, from: date))"
        case .month:
            return "\(calendar.component(.day, from: date))"
        }
    }
}
