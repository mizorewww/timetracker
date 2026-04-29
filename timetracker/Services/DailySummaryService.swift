import Foundation

struct DailySummarySnapshot: Equatable, Identifiable {
    var id: String {
        "\(Int(date.timeIntervalSince1970))-\(taskID?.uuidString ?? "all")"
    }

    let date: Date
    let taskID: UUID?
    let grossSeconds: Int
    let wallClockSeconds: Int
    let pomodoroCount: Int
    let interruptionCount: Int
    let version: Int
}

struct DailySummaryService {
    private let aggregationService = TimeAggregationService()

    func summaries(
        segments: [TimeSegment],
        interval: DateInterval,
        taskID: UUID? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        version: Int = 1
    ) -> [DailySummarySnapshot] {
        dayIntervals(in: interval, calendar: calendar).map { day in
            summary(
                segments: segments,
                day: day,
                taskID: taskID,
                now: now,
                version: version
            )
        }
    }

    func model(from snapshot: DailySummarySnapshot) -> DailySummary {
        DailySummary(
            date: snapshot.date,
            taskID: snapshot.taskID,
            grossSeconds: snapshot.grossSeconds,
            wallClockSeconds: snapshot.wallClockSeconds,
            pomodoroCount: snapshot.pomodoroCount,
            interruptionCount: snapshot.interruptionCount,
            version: snapshot.version
        )
    }

    private func summary(
        segments: [TimeSegment],
        day: DateInterval,
        taskID: UUID?,
        now: Date,
        version: Int
    ) -> DailySummarySnapshot {
        let clipped = segments.compactMap { clippedInterval(for: $0, in: day, taskID: taskID, now: now).map { (segment: $0.segment, interval: $0.interval) } }
        let gross = clipped.reduce(0) { result, item in
            result + Int(item.interval.end.timeIntervalSince(item.interval.start))
        }
        let wall = aggregationService.mergeOverlappingIntervals(clipped.map(\.interval)).reduce(0) { result, interval in
            result + Int(interval.end.timeIntervalSince(interval.start))
        }
        let pomodoroCount = clipped.filter { item in
            item.segment.source == .pomodoro &&
                item.segment.endedAt != nil &&
                item.segment.endedAt.map { day.contains($0) } == true
        }.count

        return DailySummarySnapshot(
            date: day.start,
            taskID: taskID,
            grossSeconds: gross,
            wallClockSeconds: wall,
            pomodoroCount: pomodoroCount,
            interruptionCount: 0,
            version: version
        )
    }

    private func clippedInterval(
        for segment: TimeSegment,
        in interval: DateInterval,
        taskID: UUID?,
        now: Date
    ) -> (segment: TimeSegment, interval: DateInterval)? {
        guard segment.deletedAt == nil else { return nil }
        if let taskID, segment.taskID != taskID {
            return nil
        }

        let end = segment.endedAt ?? now
        let start = max(segment.startedAt, interval.start)
        let clippedEnd = min(end, interval.end)
        guard clippedEnd > start else { return nil }
        return (segment, DateInterval(start: start, end: clippedEnd))
    }

    private func dayIntervals(in interval: DateInterval, calendar: Calendar) -> [DateInterval] {
        var result: [DateInterval] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            let next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
            let clippedStart = max(cursor, interval.start)
            let clippedEnd = min(next, interval.end)
            if clippedEnd > clippedStart {
                result.append(DateInterval(start: clippedStart, end: clippedEnd))
            }
            cursor = next
        }
        return result
    }
}
