import Foundation

struct LedgerBucketCache {
    private struct CacheKey: Hashable {
        let dayStart: Date
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
        dayIntervals(in: interval, calendar: calendar).compactMap { day in
            summary(
                segments: segments,
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
            let day = DateInterval(start: key.dayStart, duration: 24 * 60 * 60)
            return !intervals.contains { interval in
                interval.start < day.end && interval.end > day.start
            }
        }
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    private mutating func summary(
        segments: [TimeSegment],
        day: DateInterval,
        taskID: UUID?,
        now: Date,
        calendar: Calendar,
        version: Int
    ) -> DailySummarySnapshot? {
        let daySegments = segments.filter { overlaps($0, interval: day, taskID: taskID, now: now) }
        let key = CacheKey(dayStart: calendar.startOfDay(for: day.start), taskID: taskID, version: version)
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

    private func signature(for segments: [TimeSegment], now: Date) -> Int {
        var hasher = Hasher()
        for segment in segments.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(segment.id)
            hasher.combine(segment.taskID)
            hasher.combine(segment.sessionID)
            hasher.combine(segment.startedAt.timeIntervalSinceReferenceDate)
            hasher.combine((segment.endedAt ?? now).timeIntervalSinceReferenceDate)
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
        let end = segment.endedAt ?? now
        return segment.startedAt < interval.end && end > interval.start
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
