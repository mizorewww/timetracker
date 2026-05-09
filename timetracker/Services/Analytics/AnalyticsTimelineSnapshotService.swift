import Foundation

struct AnalyticsTimelineSnapshotService {
    func snapshot(
        segments: [TimeSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        taskParentPathByID: [UUID: String],
        date: Date = Date(),
        now: Date = Date(),
        calendar: Calendar = .current,
        minimumLaneGap: TimeInterval = 60
    ) -> AnalyticsTimelineSnapshot {
        let dayInterval = calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        let visibleSegments = segments
            .filter { isVisible($0, in: dayInterval, now: now) }
            .sorted { $0.startedAt < $1.startedAt }
        guard visibleSegments.isEmpty == false else { return .empty }

        let layoutItems = visibleSegments.map { segment in
            TimelineLayoutItem(
                id: segment.id,
                startedAt: segment.startedAt,
                endedAt: segment.endedAt ?? now
            )
        }
        let layout = TimelineLayoutEngine.layout(
            items: layoutItems,
            dayInterval: dayInterval,
            minimumLaneGap: minimumLaneGap
        )
        let segmentByID = Dictionary(uniqueKeysWithValues: visibleSegments.map { ($0.id, $0) })
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let sessionsByTaskID = Dictionary(grouping: sessions, by: \.taskID)
        let entries = layout.entries.enumerated().compactMap { index, layoutEntry -> AnalyticsTimelineEntry? in
            guard let segment = segmentByID[layoutEntry.id] else { return nil }
            let task = taskByID[segment.taskID]
            let fallbackTitle = sessionsByTaskID[segment.taskID]?.first?.titleSnapshot ?? AppStrings.localized("task.deleted")
            return AnalyticsTimelineEntry(
                id: segment.id,
                taskID: segment.taskID,
                title: task?.title ?? fallbackTitle,
                path: task.map { taskParentPathByID[$0.id] ?? AppStrings.rootTask } ?? AppStrings.localized("task.deleted.path"),
                iconName: task?.iconName ?? "checkmark.circle",
                colorHex: task?.colorHex ?? "0A84FF",
                startedAt: layoutEntry.item.startedAt,
                endedAt: layoutEntry.item.endedAt,
                lane: layoutEntry.lane,
                labelIndex: index,
                interval: layoutEntry.item.interval
            )
        }
        let compression = TimelineAxisCompression(
            displayInterval: layout.displayInterval,
            busyIntervals: layout.entries.map(\.item.interval)
        )

        return AnalyticsTimelineSnapshot(
            entries: entries,
            displayInterval: layout.displayInterval,
            axisCompression: compression
        )
    }

    private func isVisible(_ segment: TimeSegment, in interval: DateInterval, now: Date) -> Bool {
        let end = segment.endedAt ?? now
        return segment.deletedAt == nil && end > interval.start && segment.startedAt < interval.end
    }
}
