import Foundation

struct HourTaskActivityService {
    func hourlyActivity(
        segments: [TimeSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        date: Date = Date(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HourTaskActivity] {
        let dayInterval = calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
        let taskByID = tasks.latestByID()
        let sessionsByTaskID = Dictionary(grouping: sessions.deduplicatedByID(), by: \.taskID)

        return (0..<24).map { hour in
            let hourStart = calendar.date(byAdding: .hour, value: hour, to: dayInterval.start) ?? dayInterval.start
            let hourEnd = calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? hourStart.addingTimeInterval(3_600)
            let interval = DateInterval(start: hourStart, end: min(hourEnd, dayInterval.end))
            let secondsByTaskID = secondsByTask(
                segments: segments,
                interval: interval,
                now: now
            )
            let slices = secondsByTaskID.compactMap { taskID, seconds -> HourTaskSlice? in
                guard seconds > 0 else { return nil }
                let task = taskByID[taskID]
                let fallbackTitle = sessionsByTaskID[taskID]?.first?.titleSnapshot ?? AppStrings.localized("task.deleted")
                return HourTaskSlice(
                    taskID: taskID,
                    title: task?.title ?? fallbackTitle,
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

    private func secondsByTask(
        segments: [TimeSegment],
        interval: DateInterval,
        now: Date
    ) -> [UUID: Int] {
        segments.reduce(into: [UUID: Int]()) { result, segment in
            guard let clipped = clippedInterval(for: segment, in: interval, now: now) else { return }
            result[segment.taskID, default: 0] += Int(clipped.end.timeIntervalSince(clipped.start))
        }
    }

    private func clippedInterval(
        for segment: TimeSegment,
        in interval: DateInterval,
        now: Date
    ) -> DateInterval? {
        guard segment.deletedAt == nil else { return nil }
        let end = segment.endedAt ?? now
        let start = max(segment.startedAt, interval.start)
        let clippedEnd = min(end, interval.end)
        guard clippedEnd > start else { return nil }
        return DateInterval(start: start, end: clippedEnd)
    }
}
