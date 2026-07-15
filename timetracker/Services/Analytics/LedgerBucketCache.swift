import Foundation

struct LedgerBucketCache {
    private struct CacheKey: Hashable {
        let intervalStart: Date
        let intervalEnd: Date
        let taskID: UUID?
        let version: Int
    }

    private struct CacheEntry {
        let signature: Int
        let snapshot: DailySummarySnapshot
    }

    private let summaryService = DailySummaryService()
    private var entries: [CacheKey: CacheEntry] = [:]

    var bucketCount: Int {
        entries.count
    }

    mutating func summaries(
        segments: [TimeSegment],
        interval: DateInterval,
        taskID: UUID? = nil,
        now: Date = Date(),
        calendar: Calendar = .current,
        version: Int = 1
    ) -> [DailySummarySnapshot] {
        let days = dayIntervals(in: interval, calendar: calendar)
        let groupedSegments = segmentsByDay(
            segments,
            interval: interval,
            taskID: taskID,
            now: now,
            calendar: calendar
        )

        return days.compactMap { day in
            let dayStart = calendar.startOfDay(for: day.start)
            return summary(
                daySegments: groupedSegments[dayStart] ?? [],
                day: day,
                taskID: taskID,
                now: now,
                calendar: calendar,
                version: version
            )
        }
    }

    mutating func invalidate(intervals: [DateInterval]) {
        guard !intervals.isEmpty else { return }
        entries = entries.filter { key, _ in
            let day = DateInterval(start: key.intervalStart, end: key.intervalEnd)
            return !intervals.contains { interval in
                interval.start < day.end && interval.end > day.start
            }
        }
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    private mutating func summary(
        daySegments: [TimeSegment],
        day: DateInterval,
        taskID: UUID?,
        now: Date,
        calendar: Calendar,
        version: Int
    ) -> DailySummarySnapshot? {
        let key = CacheKey(
            intervalStart: day.start,
            intervalEnd: day.end,
            taskID: taskID,
            version: version
        )
        let signature = signature(for: daySegments, now: now)

        if let cached = entries[key], cached.signature == signature {
            return cached.snapshot
        }

        let snapshot = summaryService.summaries(
            segments: daySegments,
            interval: day,
            taskID: taskID,
            now: now,
            calendar: calendar,
            version: version
        ).first

        if let snapshot {
            entries[key] = CacheEntry(signature: signature, snapshot: snapshot)
        }
        return snapshot
    }

    private func segmentsByDay(
        _ segments: [TimeSegment],
        interval: DateInterval,
        taskID: UUID?,
        now: Date,
        calendar: Calendar
    ) -> [Date: [TimeSegment]] {
        var result: [Date: [TimeSegment]] = [:]

        for segment in segments where overlaps(segment, interval: interval, taskID: taskID, now: now) {
            guard let bounded = TrackedTimePolicy.interval(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                now: now,
                clippedTo: interval
            ) else {
                continue
            }

            var cursor = calendar.startOfDay(for: bounded.start)
            while cursor < bounded.end {
                let next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? bounded.end
                let day = DateInterval(start: max(cursor, interval.start), end: min(next, interval.end))
                if day.end > day.start, overlaps(segment, interval: day, taskID: taskID, now: now) {
                    result[calendar.startOfDay(for: day.start), default: []].append(segment)
                }
                cursor = next
            }
        }

        return result
    }

    private func signature(for segments: [TimeSegment], now: Date) -> Int {
        var hasher = Hasher()
        for segment in segments.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(segment.id)
            hasher.combine(segment.taskID)
            hasher.combine(segment.sessionID)
            hasher.combine(segment.startedAt.timeIntervalSinceReferenceDate)
            hasher.combine(
                TrackedTimePolicy.boundedEnd(endedAt: segment.endedAt, now: now)
                    .timeIntervalSinceReferenceDate
            )
            hasher.combine(segment.updatedAt.timeIntervalSinceReferenceDate)
            hasher.combine(segment.deletedAt?.timeIntervalSinceReferenceDate)
            hasher.combine(segment.sourceRaw)
        }
        return hasher.finalize()
    }

    private func overlaps(_ segment: TimeSegment, interval: DateInterval, taskID: UUID?, now: Date) -> Bool {
        guard segment.deletedAt == nil else { return false }
        if let taskID, segment.taskID != taskID {
            return false
        }
        return TrackedTimePolicy.overlaps(
            startedAt: segment.startedAt,
            endedAt: segment.endedAt,
            interval: interval,
            now: now
        )
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
