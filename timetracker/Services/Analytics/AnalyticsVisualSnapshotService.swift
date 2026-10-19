import Foundation

nonisolated struct AnalyticsVisualSnapshotService {
    func snapshot(_ input: AnalyticsVisualSnapshotInput) -> AnalyticsVisualSnapshot {
        guard input.range == .today, Task.isCancelled == false else {
            return .empty
        }
        let visible = input.segments.compactMap { segment -> AnalyticsVisualBoundedSegment? in
            guard segment.deletedAt == nil,
                  let interval = TrackedTimePolicy.interval(
                      startedAt: segment.startedAt,
                      endedAt: segment.endedAt,
                      now: input.evaluatedAt,
                      clippedTo: input.period
                  )
            else {
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
            return lhs.id < rhs.id
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
                if (0 ..< 24).contains(hour) {
                    secondsByHourAndTaskID[hour][segment.taskID, default: 0] += max(
                        0,
                        Int(end.timeIntervalSince(cursor))
                    )
                }
                cursor = end
            }
        }
        return (0 ..< 24).map { hour in
            let slices = secondsByHourAndTaskID[hour].compactMap { taskID, seconds -> HourTaskSlice? in
                guard seconds > 0 else { return nil }
                let task = input.taskByID[taskID]
                return HourTaskSlice(
                    taskID: taskID,
                    title: task?.title
                        ?? input.timelineFallbackTitleByTaskID[taskID]
                        ?? input.unavailableTaskTitle,
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
                    id: .trackedSegment($0.id),
                    startedAt: $0.interval.start,
                    endedAt: $0.interval.end
                )
            },
            dayInterval: input.period
        )
        let segmentByID = Dictionary(
            uniqueKeysWithValues: segments.map { (TimelineEntryID.trackedSegment($0.id), $0) }
        )
        let entries = layout.items.compactMap { item -> AnalyticsTimelineEntry? in
            guard let segment = segmentByID[item.id] else { return nil }
            let task = input.taskByID[segment.taskID]
            return AnalyticsTimelineEntry(
                id: .trackedSegment(segment.id),
                subject: .task(segment.taskID),
                title: task?.title
                    ?? input.timelineFallbackTitleByTaskID[segment.taskID]
                    ?? input.unavailableTaskTitle,
                path: task?.path ?? input.unavailableTaskPath,
                iconName: task?.iconName ?? "checkmark.circle",
                colorHex: task?.colorHex ?? "0A84FF",
                startedAt: item.startedAt,
                endedAt: item.endedAt,
                interval: item.interval,
                durationSeconds: max(
                    0,
                    Int(item.interval.duration)
                )
            )
        }
        return AnalyticsTimelineSnapshot(
            entries: entries,
            displayInterval: layout.displayInterval,
            axisCompression: TimelineAxisCompression(
                displayInterval: layout.displayInterval,
                busyIntervals: layout.items.map(\.interval)
            )
        )
    }
}
