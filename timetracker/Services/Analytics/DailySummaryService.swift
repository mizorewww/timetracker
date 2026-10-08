import Foundation

struct DailySummarySnapshot: Equatable, Identifiable {
    var id: String {
        "\(Int(date.timeIntervalSince1970))"
    }

    let date: Date
    let grossSeconds: Int
    let wallClockSeconds: Int
}

struct DailySummaryService {
    private let aggregationService = TimeAggregationService()

    /// Keeps the current partial day while omitting days that have not begun
    /// at the selected evaluation cutoff. Call this after cache lookup so the
    /// cache can retain stable buckets for the complete calendar period.
    func visibleSummaries(
        _ summaries: [DailySummarySnapshot],
        interval: DateInterval,
        evaluatedAt cutoff: Date
    ) -> [DailySummarySnapshot] {
        let visibleEnd = min(max(cutoff, interval.start), interval.end)
        return summaries.filter { $0.date < visibleEnd }
    }

    func summaries(
        segments: [TimeSegment],
        interval: DateInterval,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailySummarySnapshot] {
        dayIntervals(in: interval, calendar: calendar).map { day in
            summary(
                segments: segments,
                day: day,
                now: now
            )
        }
    }

    private func summary(
        segments: [TimeSegment],
        day: DateInterval,
        now: Date
    ) -> DailySummarySnapshot {
        let clipped = segments.compactMap { clippedInterval(for: $0, in: day, now: now).map { (segment: $0.segment, interval: $0.interval) } }
        let gross = clipped.reduce(0) { result, item in
            result + Int(item.interval.end.timeIntervalSince(item.interval.start))
        }
        let wall = aggregationService.mergeOverlappingIntervals(clipped.map(\.interval)).reduce(0) { result, interval in
            result + Int(interval.end.timeIntervalSince(interval.start))
        }

        return DailySummarySnapshot(
            date: day.start,
            grossSeconds: gross,
            wallClockSeconds: wall
        )
    }

    private func clippedInterval(
        for segment: TimeSegment,
        in interval: DateInterval,
        now: Date
    ) -> (segment: TimeSegment, interval: DateInterval)? {
        guard segment.deletedAt == nil else { return nil }

        guard let clipped = TrackedTimePolicy.interval(
            startedAt: segment.startedAt,
            endedAt: segment.endedAt,
            now: now,
            clippedTo: interval
        ) else {
            return nil
        }
        return (segment, clipped)
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
