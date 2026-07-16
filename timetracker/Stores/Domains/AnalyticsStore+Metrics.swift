import Foundation

extension AnalyticsStore {
    var emptyRhythm: AnalyticsRhythm {
        AnalyticsRhythm(
            activeDayCount: 0,
            dailyAverageGrossSeconds: 0,
            peakHour: nil,
            peakHourSeconds: 0,
            longestContinuousSeconds: 0,
            averageSegmentSeconds: 0,
            medianSegmentSeconds: 0,
            segmentCount: 0
        )
    }

    var emptyQuality: AnalyticsQuality {
        AnalyticsQuality(
            overlapRatio: 0,
            switchCount: 0,
            shortSegmentCount: 0,
            shortSegmentRatio: 0,
            averageSegmentSeconds: 0,
            longestContinuousSeconds: 0
        )
    }

    func previousDecisionInterval(
        for range: AnalyticsRange,
        currentInterval: DateInterval,
        calendar: Calendar
    ) -> DateInterval? {
        let component: Calendar.Component
        switch range {
        case .today:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        }
        guard let previousStart = calendar.date(
            byAdding: component,
            value: -1,
            to: currentInterval.start
        ) else {
            return nil
        }
        return DateInterval(start: previousStart, end: currentInterval.start)
    }

    func comparisonWindow(
        for range: AnalyticsRange,
        currentInterval: DateInterval,
        evaluatedAt cutoff: Date,
        calendar: Calendar
    ) -> AnalyticsComparisonWindow? {
        guard let previousInterval = previousDecisionInterval(
            for: range,
            currentInterval: currentInterval,
            calendar: calendar
        ) else {
            return nil
        }

        let currentEnd = min(max(cutoff, currentInterval.start), currentInterval.end)
        if currentEnd == currentInterval.end {
            return AnalyticsComparisonWindow(
                current: currentInterval,
                previous: previousInterval,
                basis: .completePeriods
            )
        }

        let previousEnd = matchedComparisonEnd(
            currentEnd: currentEnd,
            currentStart: currentInterval.start,
            previousInterval: previousInterval,
            calendar: calendar
        )
        return AnalyticsComparisonWindow(
            current: DateInterval(start: currentInterval.start, end: currentEnd),
            previous: DateInterval(start: previousInterval.start, end: previousEnd),
            basis: .matchedProgress
        )
    }

    /// Maps progress by calendar-day ordinal and local wall-clock components.
    /// This preserves noon across DST transitions and clamps a day that does
    /// not exist in a shorter previous month to that period's end.
    private func matchedComparisonEnd(
        currentEnd: Date,
        currentStart: Date,
        previousInterval: DateInterval,
        calendar: Calendar
    ) -> Date {
        let currentStartOfDay = calendar.startOfDay(for: currentStart)
        let currentEndStartOfDay = calendar.startOfDay(for: currentEnd)
        let dayOffset = max(
            0,
            calendar.dateComponents(
                [.day],
                from: currentStartOfDay,
                to: currentEndStartOfDay
            ).day ?? 0
        )
        guard let previousDay = calendar.date(
            byAdding: .day,
            value: dayOffset,
            to: previousInterval.start
        ) else {
            return previousInterval.start
        }

        let clock = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: currentEnd
        )
        guard let matchedSecond = calendar.date(
            bySettingHour: clock.hour ?? 0,
            minute: clock.minute ?? 0,
            second: clock.second ?? 0,
            of: previousDay
        ) else {
            return previousInterval.start
        }
        let matched = matchedSecond.addingTimeInterval(
            Double(clock.nanosecond ?? 0) / 1_000_000_000
        )
        return min(max(matched, previousInterval.start), previousInterval.end)
    }

    func rhythm(
        segments: [TimeSegment],
        interval: DateInterval,
        taskIDs: Set<UUID>?,
        now: Date,
        calendar: Calendar
    ) -> AnalyticsRhythm {
        let bounded = boundedSegments(segments, in: interval, taskIDs: taskIDs, now: now)
        guard !bounded.isEmpty else { return emptyRhythm }

        let durations = bounded.map(\.durationSeconds).filter { $0 > 0 }.sorted()
        let gross = durations.reduce(0, +)
        let dailyTotals = TimeAggregationService().secondsByDay(
            intervals: bounded.map(\.interval),
            calendar: calendar
        )
        let hourly = hourlySeconds(items: bounded, calendar: calendar)
        let peak = AnalyticsSelectionPolicy.peakHour(in: hourly)
        let longestContinuous = longestMergedDuration(items: bounded)

        return AnalyticsRhythm(
            activeDayCount: dailyTotals.count,
            dailyAverageGrossSeconds: dailyTotals.isEmpty ? 0 : gross / dailyTotals.count,
            peakHour: peak?.hour,
            peakHourSeconds: peak?.seconds ?? 0,
            longestContinuousSeconds: longestContinuous,
            averageSegmentSeconds: durations.isEmpty ? 0 : gross / durations.count,
            medianSegmentSeconds: median(durations),
            segmentCount: durations.count
        )
    }

    func quality(
        segments: [TimeSegment],
        interval: DateInterval,
        taskIDs: Set<UUID>?,
        now: Date
    ) -> AnalyticsQuality {
        let bounded = boundedSegments(segments, in: interval, taskIDs: taskIDs, now: now)
        guard !bounded.isEmpty else { return emptyQuality }

        let overview = overview(items: bounded)
        let durations = bounded.map(\.durationSeconds).filter { $0 > 0 }.sorted()
        let shortCount = durations.filter { $0 < 5 * 60 }.count
        let sorted = bounded.sorted {
            if $0.interval.start == $1.interval.start {
                return $0.segment.id.uuidString < $1.segment.id.uuidString
            }
            return $0.interval.start < $1.interval.start
        }
        let switchCount = zip(sorted, sorted.dropFirst()).reduce(0) { result, pair in
            result + (pair.0.segment.taskID == pair.1.segment.taskID ? 0 : 1)
        }

        return AnalyticsQuality(
            overlapRatio: overview.grossSeconds > 0
                ? Double(overview.overlapSeconds) / Double(overview.grossSeconds)
                : 0,
            switchCount: switchCount,
            shortSegmentCount: shortCount,
            shortSegmentRatio: durations.isEmpty ? 0 : Double(shortCount) / Double(durations.count),
            averageSegmentSeconds: durations.isEmpty ? 0 : durations.reduce(0, +) / durations.count,
            longestContinuousSeconds: longestMergedDuration(items: bounded)
        )
    }

    func seconds(
        in interval: DateInterval,
        segments: [TimeSegment],
        taskIDs: Set<UUID>?,
        mode: AggregationMode,
        now: Date
    ) -> Int {
        let items = boundedSegments(segments, in: interval, taskIDs: taskIDs, now: now)
        switch mode {
        case .gross:
            return items.reduce(0) { $0 + $1.durationSeconds }
        case .wallClock:
            return TimeAggregationService().mergeOverlappingIntervals(items.map(\.interval)).reduce(0) {
                $0 + Int($1.end.timeIntervalSince($1.start))
            }
        }
    }

    func segmentOverlaps(_ segment: TimeSegment, interval: DateInterval, now: Date) -> Bool {
        segment.deletedAt == nil && TrackedTimePolicy.overlaps(
            startedAt: segment.startedAt,
            endedAt: segment.endedAt,
            interval: interval,
            now: now
        )
    }

    func hourlySeconds(items: [AnalyticsBoundedSegment], calendar: Calendar) -> [Int: Int] {
        items.reduce(into: [Int: Int]()) { result, item in
            var cursor = item.interval.start
            while cursor < item.interval.end {
                let hour = calendar.component(.hour, from: cursor)
                let nextHour = calendar.dateInterval(of: .hour, for: cursor)?.end ?? item.interval.end
                let end = min(nextHour, item.interval.end)
                result[hour, default: 0] += max(0, Int(end.timeIntervalSince(cursor)))
                cursor = end
            }
        }
    }

    func longestMergedDuration(items: [AnalyticsBoundedSegment]) -> Int {
        TimeAggregationService().mergeOverlappingIntervals(items.map(\.interval)).map {
            Int($0.end.timeIntervalSince($0.start))
        }.max() ?? 0
    }

    func median(_ durations: [Int]) -> Int {
        guard !durations.isEmpty else { return 0 }
        let middle = durations.count / 2
        if durations.count.isMultiple(of: 2) {
            return (durations[middle - 1] + durations[middle]) / 2
        }
        return durations[middle]
    }

    func deltaText(_ seconds: Int) -> String {
        if seconds == 0 {
            return DurationFormatter.compact(0)
        }
        let prefix = seconds > 0 ? "+" : "-"
        return "\(prefix)\(DurationFormatter.compact(abs(seconds)))"
    }

    func comparisonBody(for comparison: AnalyticsComparison) -> String {
        let matchedProgress = comparison.window.basis == .matchedProgress
        if comparison.previousGrossSeconds == 0, comparison.currentGrossSeconds > 0 {
            return AppStrings.localized(
                matchedProgress
                    ? "analytics.insight.comparison.newMatchedBody"
                    : "analytics.insight.comparison.newCompleteBody"
            )
        }
        if abs(comparison.grossDeltaSeconds) < 10 * 60 {
            return AppStrings.localized(
                matchedProgress
                    ? "analytics.insight.comparison.steadyMatchedBody"
                    : "analytics.insight.comparison.steadyCompleteBody"
            )
        }
        if comparison.grossDeltaSeconds > 0 {
            return AppStrings.localized(
                matchedProgress
                    ? "analytics.insight.comparison.upMatchedBody"
                    : "analytics.insight.comparison.upCompleteBody"
            )
        }
        return AppStrings.localized(
            matchedProgress
                ? "analytics.insight.comparison.downMatchedBody"
                : "analytics.insight.comparison.downCompleteBody"
        )
    }

    func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
