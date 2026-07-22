import Foundation

struct AppleHealthTaskAnalyticsProjectionService {
    struct QueryPlan {
        let comparisonWindow: AnalyticsComparisonWindow
        let projectionInterval: DateInterval
        let queryInterval: DateInterval
    }

    private let aggregationService = TimeAggregationService()
    private let analyticsStore = AnalyticsStore()
    private let timelineProjectionService = AppleHealthTimelineProjectionService()

    func queryPlan(
        for request: TaskAnalyticsSnapshotRequest,
        now: Date,
        calendar: Calendar
    ) -> QueryPlan {
        let currentInterval = request.evaluationKey.interval
        let currentEnd = min(max(now, currentInterval.start), currentInterval.end)
        let comparisonWindow = analyticsStore.comparisonWindow(
            for: request.range,
            currentInterval: currentInterval,
            evaluatedAt: currentEnd,
            calendar: calendar
        ) ?? AnalyticsComparisonWindow(
            current: DateInterval(
                start: currentInterval.start,
                end: currentEnd
            ),
            previous: DateInterval(
                start: currentInterval.start,
                end: currentInterval.start
            ),
            basis: .matchedProgress
        )
        let projectionInterval = DateInterval(
            start: comparisonWindow.previous.start,
            end: comparisonWindow.current.end
        )
        let queryInterval = DateInterval(
            start: projectionInterval.start.addingTimeInterval(
                -AppleHealthSleepEpisodePolicy.queryContextDuration
            ),
            end: projectionInterval.end
        )
        return QueryPlan(
            comparisonWindow: comparisonWindow,
            projectionInterval: projectionInterval,
            queryInterval: queryInterval
        )
    }

    func snapshot(
        role: AppleHealthTaskRole,
        taskID: UUID,
        title: String,
        path: String,
        batch: AppleHealthSampleBatch,
        request: TaskAnalyticsSnapshotRequest,
        now: Date,
        calendar: Calendar
    ) -> TaskAnalyticsSnapshot {
        let plan = queryPlan(for: request, now: now, calendar: calendar)
        let items = timelineProjectionService.project(
            batch: batch,
            visibleInterval: plan.projectionInterval
        ).filter { $0.taskRole == role }
        let currentItems = boundedItems(
            items,
            to: plan.comparisonWindow.current
        )
        let currentIntervals = currentItems.flatMap(\.durationIntervals)
        let currentOverview = overview(for: currentIntervals)
        let previousOverview = overview(
            for: boundedItems(
                items,
                to: plan.comparisonWindow.previous
            ).flatMap(\.durationIntervals)
        )

        return TaskAnalyticsSnapshot(
            source: .appleHealth,
            taskID: taskID,
            range: request.range,
            overview: currentOverview,
            comparison: AnalyticsComparison(
                window: plan.comparisonWindow,
                currentGrossSeconds: currentOverview.grossSeconds,
                previousGrossSeconds: previousOverview.grossSeconds,
                currentWallSeconds: currentOverview.wallSeconds,
                previousWallSeconds: previousOverview.wallSeconds
            ),
            rhythm: rhythm(
                items: currentItems,
                intervals: currentIntervals,
                calendar: calendar
            ),
            quality: quality(
                items: currentItems,
                intervals: currentIntervals,
                overview: currentOverview
            ),
            directSeconds: currentOverview.grossSeconds,
            descendantSeconds: 0,
            childBreakdown: [],
            daily: dailyPoints(
                intervals: currentIntervals,
                range: request.range,
                visibleInterval: plan.comparisonWindow.current,
                calendar: calendar
            ),
            recentRecords: recentRecords(
                items: itemsOverlapping(
                    items,
                    interval: plan.comparisonWindow.current
                ),
                taskID: taskID,
                title: title,
                path: path
            )
        )
    }

    private func boundedItems(
        _ items: [AppleHealthTimelineItem],
        to interval: DateInterval
    ) -> [AppleHealthTimelineItem] {
        guard interval.duration > 0 else { return [] }
        return items.compactMap { item in
            let durationIntervals = item.durationIntervals.compactMap {
                $0.intersection(with: interval)
            }
            guard durationIntervals.isEmpty == false,
                  let envelope = item.interval.intersection(with: interval)
            else {
                return nil
            }
            return AppleHealthTimelineItem(
                id: item.id,
                subject: item.subject,
                interval: envelope,
                durationIntervals: durationIntervals
            )
        }
    }

    /// History rows belong to the selected range, but retain the original
    /// workout or sleep episode envelope. Summary/chart metrics are clipped to
    /// the range by `boundedItems`; clipping the row itself would make a
    /// cross-midnight record look shorter than the read-only Health evidence.
    private func itemsOverlapping(
        _ items: [AppleHealthTimelineItem],
        interval: DateInterval
    ) -> [AppleHealthTimelineItem] {
        guard interval.duration > 0 else { return [] }
        return items.filter { item in
            item.durationIntervals.contains { measuredInterval in
                measuredInterval.end > interval.start &&
                    measuredInterval.start < interval.end
            }
        }
    }

    private func overview(
        for intervals: [DateInterval]
    ) -> AnalyticsOverview {
        let grossSeconds = durationSeconds(intervals)
        let wallSeconds = durationSeconds(
            aggregationService.mergeOverlappingIntervals(intervals)
        )
        return AnalyticsOverview(
            grossSeconds: grossSeconds,
            wallSeconds: wallSeconds,
            overlapSeconds: max(0, grossSeconds - wallSeconds),
            pomodoroCount: 0,
            averageFocusSeconds: 0
        )
    }

    private func rhythm(
        items: [AppleHealthTimelineItem],
        intervals: [DateInterval],
        calendar: Calendar
    ) -> AnalyticsRhythm {
        let durations = itemDurations(items)
        guard durations.isEmpty == false else { return analyticsStore.emptyRhythm }
        let grossSeconds = durations.reduce(0, +)
        let dailyTotals = aggregationService.secondsByDay(
            intervals: intervals,
            calendar: calendar
        )
        let peak = AnalyticsSelectionPolicy.peakHour(
            in: hourlySeconds(intervals: intervals, calendar: calendar)
        )
        return AnalyticsRhythm(
            activeDayCount: dailyTotals.count,
            dailyAverageGrossSeconds: dailyTotals.isEmpty
                ? 0
                : grossSeconds / dailyTotals.count,
            peakHour: peak?.hour,
            peakHourSeconds: peak?.seconds ?? 0,
            longestContinuousSeconds: longestContinuousSeconds(intervals),
            averageSegmentSeconds: grossSeconds / durations.count,
            medianSegmentSeconds: analyticsStore.median(durations),
            segmentCount: durations.count
        )
    }

    private func quality(
        items: [AppleHealthTimelineItem],
        intervals: [DateInterval],
        overview: AnalyticsOverview
    ) -> AnalyticsQuality {
        let durations = itemDurations(items)
        guard durations.isEmpty == false else { return analyticsStore.emptyQuality }
        let shortCount = durations.filter { $0 < 5 * 60 }.count
        return AnalyticsQuality(
            overlapRatio: overview.grossSeconds > 0
                ? Double(overview.overlapSeconds) / Double(overview.grossSeconds)
                : 0,
            switchCount: 0,
            shortSegmentCount: shortCount,
            shortSegmentRatio: Double(shortCount) / Double(durations.count),
            averageSegmentSeconds: durations.reduce(0, +) / durations.count,
            longestContinuousSeconds: longestContinuousSeconds(intervals)
        )
    }

    private func dailyPoints(
        intervals: [DateInterval],
        range: AnalyticsRange,
        visibleInterval: DateInterval,
        calendar: Calendar
    ) -> [DailyAnalyticsPoint] {
        guard visibleInterval.duration > 0 else { return [] }
        let grossByDay = aggregationService.secondsByDay(
            intervals: intervals,
            calendar: calendar
        )
        let wallByDay = aggregationService.secondsByDay(
            intervals: aggregationService.mergeOverlappingIntervals(intervals),
            calendar: calendar
        )
        var points: [DailyAnalyticsPoint] = []
        var day = calendar.startOfDay(for: visibleInterval.start)
        while day < visibleInterval.end {
            points.append(
                DailyAnalyticsPoint(
                    date: day,
                    grossSeconds: grossByDay[day, default: 0],
                    wallSeconds: wallByDay[day, default: 0],
                    label: analyticsStore.taskDayLabel(
                        for: day,
                        range: range,
                        calendar: calendar
                    )
                )
            )
            guard let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: day
            ) else {
                break
            }
            day = nextDay
        }
        return points
    }

    private func recentRecords(
        items: [AppleHealthTimelineItem],
        taskID: UUID,
        title: String,
        path: String
    ) -> [TaskRecentRecordPoint] {
        items.sorted { lhs, rhs in
            if lhs.interval.start != rhs.interval.start {
                return lhs.interval.start > rhs.interval.start
            }
            return lhs.id.stableSortKey < rhs.id.stableSortKey
        }
        .prefix(LedgerStore.maximumRecentSegmentsPerTask)
        .map { item in
            TaskRecentRecordPoint(
                id: item.id,
                taskID: taskID,
                title: title,
                path: path,
                startedAt: item.interval.start,
                endedAt: item.interval.end,
                durationSeconds: durationSeconds(item.durationIntervals)
            )
        }
    }

    private func itemDurations(
        _ items: [AppleHealthTimelineItem]
    ) -> [Int] {
        items.map { durationSeconds($0.durationIntervals) }
            .filter { $0 > 0 }
            .sorted()
    }

    private func durationSeconds(_ intervals: [DateInterval]) -> Int {
        intervals.reduce(0) { $0 + max(0, Int($1.duration)) }
    }

    private func longestContinuousSeconds(
        _ intervals: [DateInterval]
    ) -> Int {
        aggregationService.mergeOverlappingIntervals(intervals)
            .map { max(0, Int($0.duration)) }
            .max() ?? 0
    }

    private func hourlySeconds(
        intervals: [DateInterval],
        calendar: Calendar
    ) -> [Int: Int] {
        intervals.reduce(into: [Int: Int]()) { result, interval in
            var cursor = interval.start
            while cursor < interval.end {
                let hour = calendar.component(.hour, from: cursor)
                let nextHour = calendar.dateInterval(of: .hour, for: cursor)?.end
                    ?? interval.end
                let end = min(nextHour, interval.end)
                result[hour, default: 0] += max(
                    0,
                    Int(end.timeIntervalSince(cursor))
                )
                cursor = end
            }
        }
    }
}
