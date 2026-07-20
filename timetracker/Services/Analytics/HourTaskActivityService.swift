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
        let secondsByHourAndTaskID = secondsByHourAndTask(
            segments: segments,
            dayInterval: dayInterval,
            now: now,
            calendar: calendar
        )

        return (0..<24).map { hour in
            let slices = secondsByHourAndTaskID[hour].compactMap { taskID, seconds -> HourTaskSlice? in
                guard seconds > 0 else { return nil }
                let task = taskByID[taskID]
                let fallbackTitle = sessionsByTaskID[taskID]?.first?.titleSnapshot ?? AppStrings.localized("task.unavailable")
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

    private func secondsByHourAndTask(
        segments: [TimeSegment],
        dayInterval: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> [[UUID: Int]] {
        var result = Array(repeating: [UUID: Int](), count: 24)

        for segment in segments {
            guard let clipped = clippedInterval(for: segment, in: dayInterval, now: now) else { continue }
            distribute(clipped, taskID: segment.taskID, into: &result, calendar: calendar)
        }

        return result
    }

    private func distribute(
        _ interval: DateInterval,
        taskID: UUID,
        into secondsByHourAndTaskID: inout [[UUID: Int]],
        calendar: Calendar
    ) {
        var cursor = interval.start
        while cursor < interval.end {
            let hour = calendar.component(.hour, from: cursor)
            let nextHour = calendar.dateInterval(of: .hour, for: cursor)?.end ?? interval.end
            let end = min(nextHour, interval.end)
            guard end > cursor else { break }
            if (0..<24).contains(hour) {
                secondsByHourAndTaskID[hour][taskID, default: 0] += max(0, Int(end.timeIntervalSince(cursor)))
            }
            cursor = end
        }
    }

    private func clippedInterval(
        for segment: TimeSegment,
        in interval: DateInterval,
        now: Date
    ) -> DateInterval? {
        guard segment.deletedAt == nil else { return nil }
        return TrackedTimePolicy.interval(
            startedAt: segment.startedAt,
            endedAt: segment.endedAt,
            now: now,
            clippedTo: interval
        )
    }
}
