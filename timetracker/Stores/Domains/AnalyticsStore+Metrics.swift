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
        let peak = hourly.max { $0.value < $1.value }
        let longestContinuous = longestMergedDuration(items: bounded)

        return AnalyticsRhythm(
            activeDayCount: dailyTotals.count,
            dailyAverageGrossSeconds: dailyTotals.isEmpty ? 0 : gross / dailyTotals.count,
            peakHour: peak?.key,
            peakHourSeconds: peak?.value ?? 0,
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
        if comparison.previousGrossSeconds == 0, comparison.currentGrossSeconds > 0 {
            return AppStrings.localized("analytics.insight.comparison.newBody")
        }
        if abs(comparison.grossDeltaSeconds) < 10 * 60 {
            return AppStrings.localized("analytics.insight.comparison.steadyBody")
        }
        return comparison.grossDeltaSeconds > 0
            ? AppStrings.localized("analytics.insight.comparison.upBody")
            : AppStrings.localized("analytics.insight.comparison.downBody")
    }

    func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
