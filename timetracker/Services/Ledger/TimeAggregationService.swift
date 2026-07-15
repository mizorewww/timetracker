import Foundation

struct TimeAggregationService {
    func totalSeconds(segments: [TimeSegment], mode: AggregationMode, now: Date = Date()) -> Int {
        switch mode {
        case .gross:
            return grossSeconds(segments, now: now)
        case .wallClock:
            return wallClockSeconds(segments, now: now)
        }
    }

    func grossSeconds(_ segments: [TimeSegment], now: Date = Date()) -> Int {
        segments.reduce(0) { result, segment in
            guard segment.deletedAt == nil else { return result }
            return result + TrackedTimePolicy.elapsedSeconds(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                now: now
            )
        }
    }

    func wallClockSeconds(_ segments: [TimeSegment], now: Date = Date()) -> Int {
        let intervals = segments.compactMap { segment -> DateInterval? in
            guard segment.deletedAt == nil else { return nil }
            return TrackedTimePolicy.interval(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                now: now
            )
        }

        return mergeOverlappingIntervals(intervals).reduce(0) { result, interval in
            result + Int(interval.end.timeIntervalSince(interval.start))
        }
    }

    func mergeOverlappingIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []

        for interval in sorted {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }

            if interval.start <= last.end {
                let end = max(last.end, interval.end)
                merged[merged.count - 1] = DateInterval(start: last.start, end: end)
            } else {
                merged.append(interval)
            }
        }

        return merged
    }

    /// Splits elapsed seconds at calendar-day boundaries. Calendar arithmetic is
    /// used instead of fixed 24-hour steps so DST transitions remain correct.
    func secondsByDay(
        intervals: [DateInterval],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        var totals: [Date: Int] = [:]
        for interval in intervals where interval.duration > 0 {
            var cursor = calendar.startOfDay(for: interval.start)
            while cursor < interval.end {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                let sliceStart = max(interval.start, cursor)
                let sliceEnd = min(interval.end, nextDay)
                if sliceEnd > sliceStart {
                    totals[cursor, default: 0] += Int(sliceEnd.timeIntervalSince(sliceStart))
                }
                cursor = nextDay
            }
        }
        return totals
    }
}
