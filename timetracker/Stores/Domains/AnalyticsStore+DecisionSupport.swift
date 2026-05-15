import Foundation

extension AnalyticsStore {
    func comparison(
        segments: [TimeSegment],
        range: AnalyticsRange,
        taskIDs: Set<UUID>? = nil,
        now: Date,
        calendar: Calendar
    ) -> AnalyticsComparison {
        guard let currentInterval = decisionInterval(for: range, now: now, calendar: calendar),
              let previousInterval = previousDecisionInterval(for: range, currentInterval: currentInterval, calendar: calendar) else {
            return AnalyticsComparison(
                currentGrossSeconds: 0,
                previousGrossSeconds: 0,
                currentWallSeconds: 0,
                previousWallSeconds: 0
            )
        }

        return AnalyticsComparison(
            currentGrossSeconds: seconds(in: currentInterval, segments: segments, taskIDs: taskIDs, mode: .gross, now: now),
            previousGrossSeconds: seconds(in: previousInterval, segments: segments, taskIDs: taskIDs, mode: .gross, now: now),
            currentWallSeconds: seconds(in: currentInterval, segments: segments, taskIDs: taskIDs, mode: .wallClock, now: now),
            previousWallSeconds: seconds(in: previousInterval, segments: segments, taskIDs: taskIDs, mode: .wallClock, now: now)
        )
    }

    func rhythm(
        segments: [TimeSegment],
        range: AnalyticsRange,
        taskIDs: Set<UUID>? = nil,
        now: Date,
        calendar: Calendar
    ) -> AnalyticsRhythm {
        guard let interval = decisionInterval(for: range, now: now, calendar: calendar) else {
            return emptyRhythm
        }
        return rhythm(segments: segments, interval: interval, taskIDs: taskIDs, now: now, calendar: calendar)
    }

    func quality(
        segments: [TimeSegment],
        range: AnalyticsRange,
        taskIDs: Set<UUID>? = nil,
        now: Date,
        calendar: Calendar
    ) -> AnalyticsQuality {
        guard let interval = decisionInterval(for: range, now: now, calendar: calendar) else {
            return emptyQuality
        }
        return quality(segments: segments, interval: interval, taskIDs: taskIDs, now: now)
    }

    func rootBreakdown(
        segments: [TimeSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        taskPathByID: [UUID: String],
        range: AnalyticsRange,
        now: Date,
        calendar: Calendar
    ) -> [AnalyticsGroupBreakdownPoint] {
        guard let interval = decisionInterval(for: range, now: now, calendar: calendar) else { return [] }
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let sessionsByTaskID = Dictionary(grouping: sessions, by: \.taskID)
        let bounded = boundedSegments(segments, in: interval, now: now)
        let grouped = Dictionary(grouping: bounded) { item -> String in
            guard let task = taskByID[item.segment.taskID],
                  let root = rootTask(for: task, taskByID: taskByID) else {
                return "deleted-\(item.segment.taskID.uuidString)"
            }
            return root.id.uuidString
        }

        return grouped.compactMap { groupID, items -> AnalyticsGroupBreakdownPoint? in
            guard let first = items.first else { return nil }
            let task = taskByID[first.segment.taskID]
            let root = task.flatMap { rootTask(for: $0, taskByID: taskByID) }
            let title = root?.title ?? sessionsByTaskID[first.segment.taskID]?.first?.titleSnapshot ?? AppStrings.localized("task.deleted")
            let path = root.flatMap { taskPathByID[$0.id] } ?? AppStrings.localized("task.deleted.path")
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
        segments: [TimeSegment],
        tasks: [TaskNode],
        taskCategories: [TaskCategory],
        taskCategoryAssignments: [TaskCategoryAssignment],
        range: AnalyticsRange,
        now: Date,
        calendar: Calendar
    ) -> [AnalyticsGroupBreakdownPoint] {
        guard let interval = decisionInterval(for: range, now: now, calendar: calendar) else { return [] }
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let categoryByID = Dictionary(uniqueKeysWithValues: taskCategories.filter { $0.deletedAt == nil }.map { ($0.id, $0) })
        let categoryIDByRootTaskID = taskCategoryAssignments
            .filter { $0.deletedAt == nil }
            .sorted { $0.updatedAt < $1.updatedAt }
            .reduce(into: [UUID: UUID]()) { result, assignment in
                result[assignment.taskID] = assignment.categoryID
            }
        let bounded = boundedSegments(segments, in: interval, now: now)
        let grouped = Dictionary(grouping: bounded) { item -> String in
            guard let task = taskByID[item.segment.taskID],
                  let root = rootTask(for: task, taskByID: taskByID),
                  let categoryID = categoryIDByRootTaskID[root.id],
                  categoryByID[categoryID] != nil else {
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

    func insights(
        overview: AnalyticsOverview,
        comparison: AnalyticsComparison,
        rhythm: AnalyticsRhythm,
        quality: AnalyticsQuality,
        taskBreakdown: [TaskAnalyticsPoint]
    ) -> [AnalyticsInsight] {
        guard overview.grossSeconds > 0 else {
            return [
                AnalyticsInsight(
                    id: "no-data",
                    title: AppStrings.localized("analytics.insight.noData.title"),
                    value: DurationFormatter.compact(0),
                    body: AppStrings.localized("analytics.insight.noData.body"),
                    severity: .neutral,
                    taskID: nil
                )
            ]
        }

        var result: [AnalyticsInsight] = []
        if let topTask = taskBreakdown.first {
            let percent = Int((Double(topTask.grossSeconds) / Double(max(overview.grossSeconds, 1))) * 100)
            result.append(
                AnalyticsInsight(
                    id: "top-task",
                    title: AppStrings.localized("analytics.insight.topTask.title"),
                    value: topTask.title,
                    body: String(
                        format: AppStrings.localized("analytics.insight.topTask.bodyFormat"),
                        DurationFormatter.compact(topTask.grossSeconds),
                        percent
                    ),
                    severity: .neutral,
                    taskID: topTask.taskID
                )
            )
        }

        result.append(
            AnalyticsInsight(
                id: "comparison",
                title: AppStrings.localized("analytics.insight.comparison.title"),
                value: deltaText(comparison.grossDeltaSeconds),
                body: comparisonBody(for: comparison),
                severity: comparison.grossDeltaSeconds >= 0 ? .neutral : .positive,
                taskID: nil
            )
        )

        if quality.overlapRatio >= 0.15 {
            result.append(
                AnalyticsInsight(
                    id: "quality-overlap",
                    title: AppStrings.localized("analytics.insight.quality.title"),
                    value: percentText(quality.overlapRatio),
                    body: AppStrings.localized("analytics.insight.quality.overlapBody"),
                    severity: quality.overlapRatio >= 0.3 ? .critical : .warning,
                    taskID: nil
                )
            )
        } else if quality.shortSegmentRatio >= 0.35 {
            result.append(
                AnalyticsInsight(
                    id: "quality-fragmented",
                    title: AppStrings.localized("analytics.insight.quality.title"),
                    value: percentText(quality.shortSegmentRatio),
                    body: AppStrings.localized("analytics.insight.quality.fragmentedBody"),
                    severity: .warning,
                    taskID: nil
                )
            )
        } else {
            result.append(
                AnalyticsInsight(
                    id: "quality-steady",
                    title: AppStrings.localized("analytics.insight.quality.title"),
                    value: DurationFormatter.compact(rhythm.longestContinuousSeconds),
                    body: AppStrings.localized("analytics.insight.quality.steadyBody"),
                    severity: .positive,
                    taskID: nil
                )
            )
        }

        if let nextTask = taskBreakdown.first {
            result.append(
                AnalyticsInsight(
                    id: "next-action",
                    title: AppStrings.localized("analytics.insight.next.title"),
                    value: nextTask.title,
                    body: AppStrings.localized("analytics.insight.next.body"),
                    severity: .neutral,
                    taskID: nextTask.taskID
                )
            )
        }

        return Array(result.prefix(4))
    }

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
        let interval = decisionInterval(for: range, now: now, calendar: calendar)
            ?? DateInterval(start: .distantPast, end: now)
        let filtered = segments.filter { taskIDs.contains($0.taskID) && segmentOverlaps($0, interval: interval, now: now) }
        let bounded = boundedSegments(filtered, in: interval, taskIDs: taskIDs, now: now)
        let overview = overview(items: bounded)
        let comparison = comparison(segments: segments, range: range, taskIDs: taskIDs, now: now, calendar: calendar)
        let rhythm = rhythm(segments: segments, interval: interval, taskIDs: taskIDs, now: now, calendar: calendar)
        let quality = quality(segments: segments, interval: interval, taskIDs: taskIDs, now: now)
        let daily = DailySummaryService().summaries(
            segments: filtered,
            interval: interval,
            now: now,
            calendar: calendar
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
            directSeconds: seconds(in: interval, segments: segments, taskIDs: [task.id], mode: .gross, now: now),
            descendantSeconds: seconds(in: interval, segments: segments, taskIDs: taskIDs.subtracting([task.id]), mode: .gross, now: now),
            childBreakdown: taskChildBreakdown(
                task: task,
                taskIDs: taskIDs,
                tasks: tasks,
                segments: segments,
                interval: interval,
                now: now
            ),
            daily: daily,
            recentRecords: recentRecords(
                segments: segments,
                sessions: sessions,
                tasks: tasks,
                taskIDs: taskIDs,
                taskPathByID: taskPathByID,
                now: now
            ),
            rangeSegments: filtered
        )
    }
}

private extension AnalyticsStore {
    var emptyRhythm: AnalyticsRhythm {
        AnalyticsRhythm(
            activeDayCount: 0,
            dailyAverageGrossSeconds: 0,
            peakHour: nil,
            peakHourSeconds: 0,
            longestContinuousSeconds: 0,
            averageSegmentSeconds: 0,
            medianSegmentSeconds: 0,
            segmentCount: 0
        )
    }

    var emptyQuality: AnalyticsQuality {
        AnalyticsQuality(
            overlapRatio: 0,
            switchCount: 0,
            shortSegmentCount: 0,
            shortSegmentRatio: 0,
            averageSegmentSeconds: 0,
            longestContinuousSeconds: 0
        )
    }

    func decisionInterval(for range: AnalyticsRange, now: Date, calendar: Calendar) -> DateInterval? {
        switch range {
        case .today:
            return calendar.dateInterval(of: .day, for: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now)
        }
    }

    func previousDecisionInterval(
        for range: AnalyticsRange,
        currentInterval: DateInterval,
        calendar: Calendar
    ) -> DateInterval? {
        let component: Calendar.Component
        switch range {
        case .today:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        }
        guard let previousStart = calendar.date(byAdding: component, value: -1, to: currentInterval.start) else {
            return nil
        }
        return DateInterval(start: previousStart, end: currentInterval.start)
    }

    func rhythm(
        segments: [TimeSegment],
        interval: DateInterval,
        taskIDs: Set<UUID>?,
        now: Date,
        calendar: Calendar
    ) -> AnalyticsRhythm {
        let bounded = boundedSegments(segments, in: interval, taskIDs: taskIDs, now: now)
        guard !bounded.isEmpty else { return emptyRhythm }

        let durations = bounded.map(\.durationSeconds).filter { $0 > 0 }.sorted()
        let gross = durations.reduce(0, +)
        let activeDays = Set(bounded.map { calendar.startOfDay(for: $0.interval.start) })
        let hourly = hourlySeconds(items: bounded, calendar: calendar)
        let peak = hourly.max { $0.value < $1.value }
        let longestContinuous = longestMergedDuration(items: bounded)

        return AnalyticsRhythm(
            activeDayCount: activeDays.count,
            dailyAverageGrossSeconds: activeDays.isEmpty ? 0 : gross / activeDays.count,
            peakHour: peak?.key,
            peakHourSeconds: peak?.value ?? 0,
            longestContinuousSeconds: longestContinuous,
            averageSegmentSeconds: durations.isEmpty ? 0 : gross / durations.count,
            medianSegmentSeconds: median(durations),
            segmentCount: durations.count
        )
    }

    func quality(
        segments: [TimeSegment],
        interval: DateInterval,
        taskIDs: Set<UUID>?,
        now: Date
    ) -> AnalyticsQuality {
        let bounded = boundedSegments(segments, in: interval, taskIDs: taskIDs, now: now)
        guard !bounded.isEmpty else { return emptyQuality }

        let overview = overview(items: bounded)
        let durations = bounded.map(\.durationSeconds).filter { $0 > 0 }.sorted()
        let shortCount = durations.filter { $0 < 5 * 60 }.count
        let sorted = bounded.sorted {
            if $0.interval.start == $1.interval.start {
                return $0.segment.id.uuidString < $1.segment.id.uuidString
            }
            return $0.interval.start < $1.interval.start
        }
        let switchCount = zip(sorted, sorted.dropFirst()).reduce(0) { result, pair in
            result + (pair.0.segment.taskID == pair.1.segment.taskID ? 0 : 1)
        }

        return AnalyticsQuality(
            overlapRatio: overview.grossSeconds > 0 ? Double(overview.overlapSeconds) / Double(overview.grossSeconds) : 0,
            switchCount: switchCount,
            shortSegmentCount: shortCount,
            shortSegmentRatio: durations.isEmpty ? 0 : Double(shortCount) / Double(durations.count),
            averageSegmentSeconds: durations.isEmpty ? 0 : durations.reduce(0, +) / durations.count,
            longestContinuousSeconds: longestMergedDuration(items: bounded)
        )
    }

    func overview(items: [AnalyticsBoundedSegment]) -> AnalyticsOverview {
        let gross = items.reduce(0) { $0 + $1.durationSeconds }
        let intervals = items.map(\.interval)
        let wall = TimeAggregationService().mergeOverlappingIntervals(intervals).reduce(0) {
            $0 + Int($1.end.timeIntervalSince($1.start))
        }
        let focusItems = items.filter { $0.segment.source == .pomodoro }
        let focusSeconds = focusItems.reduce(0) { $0 + $1.durationSeconds }
        return AnalyticsOverview(
            grossSeconds: gross,
            wallSeconds: wall,
            overlapSeconds: max(0, gross - wall),
            pomodoroCount: focusItems.filter { $0.segment.endedAt != nil }.count,
            averageFocusSeconds: focusItems.isEmpty ? 0 : focusSeconds / focusItems.count
        )
    }

    func seconds(
        in interval: DateInterval,
        segments: [TimeSegment],
        taskIDs: Set<UUID>?,
        mode: AggregationMode,
        now: Date
    ) -> Int {
        let items = boundedSegments(segments, in: interval, taskIDs: taskIDs, now: now)
        switch mode {
        case .gross:
            return items.reduce(0) { $0 + $1.durationSeconds }
        case .wallClock:
            return TimeAggregationService().mergeOverlappingIntervals(items.map(\.interval)).reduce(0) {
                $0 + Int($1.end.timeIntervalSince($1.start))
            }
        }
    }

    func boundedSegments(
        _ segments: [TimeSegment],
        in interval: DateInterval,
        taskIDs: Set<UUID>? = nil,
        now: Date
    ) -> [AnalyticsBoundedSegment] {
        segments.compactMap { segment in
            guard segment.deletedAt == nil else { return nil }
            if let taskIDs, !taskIDs.contains(segment.taskID) {
                return nil
            }
            let end = segment.endedAt ?? now
            guard segment.startedAt < interval.end, end > interval.start else { return nil }
            let start = max(segment.startedAt, interval.start)
            let clippedEnd = min(end, interval.end)
            guard clippedEnd > start else { return nil }
            return AnalyticsBoundedSegment(
                segment: segment,
                interval: DateInterval(start: start, end: clippedEnd)
            )
        }
    }

    func segmentOverlaps(_ segment: TimeSegment, interval: DateInterval, now: Date) -> Bool {
        let end = segment.endedAt ?? now
        return segment.deletedAt == nil && segment.startedAt < interval.end && end > interval.start
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
        let wall = TimeAggregationService().mergeOverlappingIntervals(items.map(\.interval)).reduce(0) {
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

    func rootTask(for task: TaskNode, taskByID: [UUID: TaskNode]) -> TaskNode? {
        var cursor = task
        var visited: Set<UUID> = [task.id]
        while let parentID = cursor.parentID,
              !visited.contains(parentID),
              let parent = taskByID[parentID],
              parent.deletedAt == nil {
            visited.insert(parentID)
            cursor = parent
        }
        return cursor
    }

    func taskAndDescendantIDs(for taskID: UUID, childrenByParentID: [UUID?: [TaskNode]], visited: Set<UUID> = []) -> Set<UUID> {
        guard !visited.contains(taskID) else { return [] }
        let nextVisited = visited.union([taskID])
        let childIDs = (childrenByParentID[taskID] ?? []).reduce(into: Set<UUID>()) { result, child in
            result.formUnion(taskAndDescendantIDs(for: child.id, childrenByParentID: childrenByParentID, visited: nextVisited))
        }
        return childIDs.union([taskID])
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
        var points: [AnalyticsGroupBreakdownPoint] = []
        let directItems = boundedSegments(segments, in: interval, taskIDs: [task.id], now: now)
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
            let childIDs = taskAndDescendantIDs(for: child.id, childrenByParentID: childrenByParentID).intersection(taskIDs)
            let items = boundedSegments(segments, in: interval, taskIDs: childIDs, now: now)
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
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let sessionsByTaskID = Dictionary(grouping: sessions, by: \.taskID)
        return segments
            .filter { taskIDs.contains($0.taskID) && $0.deletedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(8)
            .map { segment in
                let task = taskByID[segment.taskID]
                let end = segment.endedAt ?? now
                return TaskRecentRecordPoint(
                    id: segment.id,
                    taskID: segment.taskID,
                    title: task?.title ?? sessionsByTaskID[segment.taskID]?.first?.titleSnapshot ?? AppStrings.localized("task.deleted"),
                    path: task.flatMap { taskPathByID[$0.id] } ?? AppStrings.localized("task.deleted.path"),
                    startedAt: segment.startedAt,
                    endedAt: segment.endedAt,
                    durationSeconds: max(0, Int(end.timeIntervalSince(segment.startedAt)))
                )
            }
    }

    func hourlySeconds(items: [AnalyticsBoundedSegment], calendar: Calendar) -> [Int: Int] {
        items.reduce(into: [Int: Int]()) { result, item in
            var cursor = item.interval.start
            while cursor < item.interval.end {
                let hour = calendar.component(.hour, from: cursor)
                let nextHour = calendar.dateInterval(of: .hour, for: cursor)?.end ?? item.interval.end
                let end = min(nextHour, item.interval.end)
                result[hour, default: 0] += max(0, Int(end.timeIntervalSince(cursor)))
                cursor = end
            }
        }
    }

    func longestMergedDuration(items: [AnalyticsBoundedSegment]) -> Int {
        TimeAggregationService().mergeOverlappingIntervals(items.map(\.interval)).map {
            Int($0.end.timeIntervalSince($0.start))
        }.max() ?? 0
    }

    func median(_ durations: [Int]) -> Int {
        guard !durations.isEmpty else { return 0 }
        let middle = durations.count / 2
        if durations.count.isMultiple(of: 2) {
            return (durations[middle - 1] + durations[middle]) / 2
        }
        return durations[middle]
    }

    func deltaText(_ seconds: Int) -> String {
        if seconds == 0 {
            return DurationFormatter.compact(0)
        }
        let prefix = seconds > 0 ? "+" : "-"
        return "\(prefix)\(DurationFormatter.compact(abs(seconds)))"
    }

    func comparisonBody(for comparison: AnalyticsComparison) -> String {
        if comparison.previousGrossSeconds == 0, comparison.currentGrossSeconds > 0 {
            return AppStrings.localized("analytics.insight.comparison.newBody")
        }
        if abs(comparison.grossDeltaSeconds) < 10 * 60 {
            return AppStrings.localized("analytics.insight.comparison.steadyBody")
        }
        return comparison.grossDeltaSeconds > 0
            ? AppStrings.localized("analytics.insight.comparison.upBody")
            : AppStrings.localized("analytics.insight.comparison.downBody")
    }

    func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
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

private struct AnalyticsBoundedSegment {
    let segment: TimeSegment
    let interval: DateInterval

    var durationSeconds: Int {
        max(0, Int(interval.end.timeIntervalSince(interval.start)))
    }
}
