import Foundation

struct ForecastingService {
    static let maximumRecentDayCount = 366

    private let aggregationService = TimeAggregationService()

    func recentDailyAvailableSeconds(
        segments: [TimeSegment],
        now: Date = Date(),
        days: Int = 14,
        calendar: Calendar = .current
    ) -> Int {
        let dayCount = min(max(1, days), Self.maximumRecentDayCount)
        let todayStart = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return 0 }
        guard let start = calendar.date(byAdding: .day, value: -dayCount, to: end) else { return 0 }
        let interval = DateInterval(start: start, end: end)
        let recent = segments.filter { segment in
            segment.deletedAt == nil &&
            segment.startedAt < interval.end &&
            (segment.endedAt ?? now) > interval.start
        }
        guard !recent.isEmpty else { return 0 }

        var dayTotals: [Date: Int] = [:]
        for segment in recent {
            guard let clipped = clippedInterval(for: segment, in: interval, now: now) else { continue }
            var cursor = calendar.startOfDay(for: clipped.start)
            while cursor < clipped.end {
                let next = min(calendar.date(byAdding: .day, value: 1, to: cursor) ?? clipped.end, clipped.end)
                let dayStart = max(cursor, clipped.start)
                let seconds = max(0, Int(next.timeIntervalSince(dayStart)))
                dayTotals[cursor, default: 0] += seconds
                cursor = next
            }
        }

        let activeDays = dayTotals.values.filter { $0 > 0 }
        guard !activeDays.isEmpty else { return 0 }
        return activeDays.reduce(0, +) / activeDays.count
    }

    private func clippedInterval(for segment: TimeSegment, in interval: DateInterval, now: Date) -> DateInterval? {
        let end = segment.endedAt ?? now
        let start = max(segment.startedAt, interval.start)
        let clippedEnd = min(end, interval.end)
        guard clippedEnd > start else { return nil }
        return DateInterval(start: start, end: clippedEnd)
    }
}
