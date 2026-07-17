import Foundation

nonisolated struct AnalyticsVisualSnapshotService {
    func snapshot(_ input: AnalyticsVisualSnapshotInput) -> AnalyticsVisualSnapshot {
        guard input.range == .today, Task.isCancelled == false else {
            return .empty
        }
        let visible = input.segments.compactMap { segment -> AnalyticsVisualBoundedSegment? in
            guard segment.deletedAt == nil,
                  let interval = clippedInterval(
                      startedAt: segment.startedAt,
                      endedAt: segment.endedAt,
                      in: input.period,
                      evaluatedAt: input.evaluatedAt
                  ) else {
                return nil
            }
            return AnalyticsVisualBoundedSegment(
                id: segment.id,
                taskID: segment.taskID,
                interval: interval
            )
        }
        .sorted { lhs, rhs in
            if lhs.interval.start != rhs.interval.start {
                return lhs.interval.start < rhs.interval.start
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard Task.isCancelled == false else { return .empty }
        guard visible.isEmpty == false else {
            return AnalyticsVisualSnapshot(
                todayActivity: hourlyActivity([], input: input),
                timeline: .empty,
                overlaps: []
            )
        }
        return AnalyticsVisualSnapshot(
            todayActivity: hourlyActivity(visible, input: input),
            timeline: timeline(visible, input: input),
            overlaps: AnalyticsVisualOverlapService().overlaps(visible, input: input)
        )
    }

    private func hourlyActivity(
        _ segments: [AnalyticsVisualBoundedSegment],
        input: AnalyticsVisualSnapshotInput
    ) -> [HourTaskActivity] {
        var secondsByHourAndTaskID = Array(repeating: [UUID: Int](), count: 24)
        for segment in segments {
            guard Task.isCancelled == false else { return [] }
            var cursor = segment.interval.start
            while cursor < segment.interval.end {
                let hour = input.calendar.component(.hour, from: cursor)
                let nextHour = input.calendar.dateInterval(of: .hour, for: cursor)?.end
                    ?? segment.interval.end
                let end = min(nextHour, segment.interval.end)
                guard end > cursor else { break }
                if (0..<24).contains(hour) {
                    secondsByHourAndTaskID[hour][segment.taskID, default: 0] += max(
                        0,
                        Int(end.timeIntervalSince(cursor))
                    )
                }
                cursor = end
            }
        }
        return (0..<24).map { hour in
            let slices = secondsByHourAndTaskID[hour].compactMap { taskID, seconds -> HourTaskSlice? in
                guard seconds > 0 else { return nil }
                let task = input.taskByID[taskID]
                return HourTaskSlice(
                    taskID: taskID,
                    title: task?.title
                        ?? input.timelineFallbackTitleByTaskID[taskID]
                        ?? input.deletedTaskTitle,
                    symbolName: task?.iconName ?? "checkmark.circle",
                    colorHex: task?.colorHex ?? "0A84FF",
                    seconds: seconds
                )
            }
            .sorted { first, second in
                if first.seconds == second.seconds {
                    return first.title.localizedStandardCompare(second.title) == .orderedAscending
                }
                return first.seconds > second.seconds
            }
            return HourTaskActivity(hour: hour, slices: slices)
        }
    }

    private func timeline(
        _ segments: [AnalyticsVisualBoundedSegment],
        input: AnalyticsVisualSnapshotInput
    ) -> AnalyticsTimelineSnapshot {
        guard Task.isCancelled == false else { return .empty }
        let layout = TimelineLayoutEngine.layout(
            items: segments.map {
                TimelineLayoutItem(
                    id: $0.id,
                    startedAt: $0.interval.start,
                    endedAt: $0.interval.end
                )
            },
            dayInterval: input.period
        )
        let segmentByID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        let entries = layout.entries.enumerated().compactMap { index, layoutEntry -> AnalyticsTimelineEntry? in
            guard let segment = segmentByID[layoutEntry.id] else { return nil }
            let task = input.taskByID[segment.taskID]
            return AnalyticsTimelineEntry(
                id: segment.id,
                taskID: segment.taskID,
                title: task?.title
                    ?? input.timelineFallbackTitleByTaskID[segment.taskID]
                    ?? input.deletedTaskTitle,
                path: task?.path ?? input.deletedTaskPath,
                iconName: task?.iconName ?? "checkmark.circle",
                colorHex: task?.colorHex ?? "0A84FF",
                startedAt: layoutEntry.item.startedAt,
                endedAt: layoutEntry.item.endedAt,
                lane: layoutEntry.lane,
                labelIndex: index,
                interval: layoutEntry.item.interval
            )
        }
        return AnalyticsTimelineSnapshot(
            entries: entries,
            displayInterval: layout.displayInterval,
            axisCompression: TimelineAxisCompression(
                displayInterval: layout.displayInterval,
                busyIntervals: layout.entries.map(\.item.interval)
            )
        )
    }

    private func clippedInterval(
        startedAt: Date,
        endedAt: Date?,
        in bounds: DateInterval,
        evaluatedAt cutoff: Date
    ) -> DateInterval? {
        let start = max(startedAt, bounds.start)
        let end = min(min(endedAt ?? cutoff, cutoff), bounds.end)
        guard start < cutoff, end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}
