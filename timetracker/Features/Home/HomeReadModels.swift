import Foundation

nonisolated struct TodayHomeContentCacheKey: Equatable, Sendable {
    let analyticsRevision: UInt
    let taskReadModelRevision: UInt64
    let selectedTaskID: UUID?
    let quickStartTaskIDs: [UUID]
    let countdownEventIDs: [UUID]
    let quickStartLimit: Int
    let forecastLimit: Int
}

extension TimeTrackerStore {
    /// Today's page read model, cached by its observable inputs.
    ///
    /// The compact shell re-evaluates every tab's body on tab switches, so
    /// Today's body (which builds `TodayHomeContent`, including per-task
    /// ledger activity ranking) used to pay its full cost on every switch.
    /// The cache key covers every store value the content reads; body
    /// evaluations only compare the key (a few revision reads + UUID arrays).
    func todayHomeContent(
        quickStartLimit: Int = 4,
        forecastLimit: Int = 3
    ) -> TodayHomeContent {
        let key = TodayHomeContentCacheKey(
            analyticsRevision: analyticsRevision,
            taskReadModelRevision: taskReadModelRevision,
            selectedTaskID: selectedTaskID,
            quickStartTaskIDs: preferences.quickStartTaskIDs,
            countdownEventIDs: countdownEvents.map(\.id),
            quickStartLimit: quickStartLimit,
            forecastLimit: forecastLimit
        )
        if let cached = todayHomeContentCache, cached.key == key {
            return cached.content
        }
        let content = TodayHomeContent(
            store: self,
            quickStartLimit: quickStartLimit,
            forecastLimit: forecastLimit
        )
        todayHomeContentCache = (key: key, content: content)
        return content
    }
}

struct TodayHomeContent {
    let activeSegments: [TimeSegment]
    let quickStartTasks: [TaskNode]
    let forecasts: [ForecastDisplayItem]
    let timelineSegments: [TimeSegment]
    let countdownEvents: [CountdownEvent]

    var hasSupportingContent: Bool {
        !forecasts.isEmpty || !countdownEvents.isEmpty
    }

    @MainActor
    init(
        store: TimeTrackerStore,
        quickStartLimit: Int = 4,
        forecastLimit: Int = 3
    ) {
        activeSegments = store.activeSegments
        #if DEBUG
        if homeTimelineUsesFixedUITestReferenceDate {
            let referenceDate = homeTimelineReferenceDate(liveDate: Date())
            timelineSegments = store.timelineSegments(
                for: referenceDate,
                now: referenceDate
            )
        } else {
            timelineSegments = store.timelineSegments
        }
        #else
        timelineSegments = store.timelineSegments
        #endif

        let pinnedTasks = store.preferences.quickStartTaskIDs
            .compactMap { store.task(for: $0) }
            .filter(store.isTaskAvailableForTracking)
            .deduplicatedByID()
        let recentTasks = store.frequentRecentTasks(
            excluding: Set(pinnedTasks.map(\.id)),
            limit: max(0, quickStartLimit - pinnedTasks.count)
        )
        quickStartTasks = Array(
            (pinnedTasks + recentTasks)
                .deduplicatedByID()
                .prefix(max(0, quickStartLimit))
        )

        let candidates = store.forecastDisplayItems()
        if let selectedTaskID = store.selectedTaskID,
           let selected = store.forecastDisplayItem(for: selectedTaskID)
        {
            forecasts = Array(
                ([selected] + candidates.filter { $0.taskID != selected.taskID })
                    .prefix(max(0, forecastLimit))
            )
        } else {
            forecasts = Array(candidates.prefix(max(0, forecastLimit)))
        }

        countdownEvents = Self.sortedCountdownEvents(store.countdownEvents)
    }

    static func sortedCountdownEvents(_ events: [CountdownEvent]) -> [CountdownEvent] {
        events.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            let titleComparison = lhs.title.localizedStandardCompare(rhs.title)
            if titleComparison != .orderedSame {
                return titleComparison == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}

nonisolated struct TodayMetricsSnapshot: Equatable, Sendable {
    let grossSeconds: Int
    let wallSeconds: Int
    let previousGrossSeconds: Int
    let previousWallSeconds: Int
}

struct WeeklyGrossTimeSnapshot {
    let interval: DateInterval
    let daily: [DailyAnalyticsPoint]
    let requiresLiveRefresh: Bool

    var totalGrossSeconds: Int {
        daily.reduce(0) { $0 + $1.grossSeconds }
    }

    var totalWallSeconds: Int {
        daily.reduce(0) { $0 + $1.wallSeconds }
    }

    var hasTrackedTime: Bool {
        daily.contains { $0.grossSeconds > 0 }
    }
}

extension TimeTrackerStore {
    /// Today's gross/wall totals, cached by ledger revision + minute bucket.
    ///
    /// Tab switches re-evaluate every mounted page, and the metrics row's
    /// static branch plus the 30 s timeline can both query in the same
    /// minute; the cache collapses those into one interval projection.
    func todayMetricsSnapshot(
        now: Date,
        calendar: Calendar = .current
    ) -> TodayMetricsSnapshot {
        let minuteBucket = Int(now.timeIntervalSinceReferenceDate / 60)
        if let cached = todayMetricsSnapshotCache,
           cached.key.revision == analyticsRevision,
           cached.key.minuteBucket == minuteBucket
        {
            return cached.snapshot
        }
        let snapshot = computeTodayMetricsSnapshot(now: now, calendar: calendar)
        todayMetricsSnapshotCache = (
            key: (revision: analyticsRevision, minuteBucket: minuteBucket),
            snapshot: snapshot
        )
        return snapshot
    }

    private func computeTodayMetricsSnapshot(
        now: Date,
        calendar: Calendar
    ) -> TodayMetricsSnapshot {
        guard let todayInterval = calendar.dateInterval(of: .day, for: now),
              let previousDate = calendar.date(byAdding: .day, value: -1, to: now),
              let previousInterval = calendar.dateInterval(of: .day, for: previousDate)
        else {
            return TodayMetricsSnapshot(
                grossSeconds: 0,
                wallSeconds: 0,
                previousGrossSeconds: 0,
                previousWallSeconds: 0
            )
        }

        let combinedInterval = DateInterval(start: previousInterval.start, end: todayInterval.end)
        let segments = visibleSegments(overlapping: combinedInterval, now: now)
            .visibleDeduplicatedByID()
        var todayGrossSeconds = 0
        var previousGrossSeconds = 0
        var todayIntervals: [DateInterval] = []
        var previousIntervals: [DateInterval] = []

        for segment in segments {
            if let interval = TrackedTimePolicy.interval(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                now: now,
                clippedTo: todayInterval
            ) {
                todayGrossSeconds += Int(interval.duration)
                todayIntervals.append(interval)
            }

            if let interval = TrackedTimePolicy.interval(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                now: now,
                clippedTo: previousInterval
            ) {
                previousGrossSeconds += Int(interval.duration)
                previousIntervals.append(interval)
            }
        }

        let aggregationService = TimeAggregationService()
        func wallSeconds(for intervals: [DateInterval]) -> Int {
            aggregationService.mergeOverlappingIntervals(intervals).reduce(0) {
                $0 + Int($1.duration)
            }
        }

        return TodayMetricsSnapshot(
            grossSeconds: todayGrossSeconds,
            wallSeconds: wallSeconds(for: todayIntervals),
            previousGrossSeconds: previousGrossSeconds,
            previousWallSeconds: wallSeconds(for: previousIntervals)
        )
    }

    func weeklyGrossTimeSnapshot(
        now: Date,
        calendar: Calendar = .current
    ) -> WeeklyGrossTimeSnapshot {
        let evaluation = AnalyticsRange.week.evaluation(
            referenceDate: now,
            liveNow: now,
            calendar: calendar
        )
        let interval = evaluation.interval
        guard interval.duration > 0 else {
            return WeeklyGrossTimeSnapshot(
                interval: interval,
                daily: [],
                requiresLiveRefresh: false
            )
        }

        let segments = visibleSegments(
            overlapping: interval,
            evaluatedAt: interval.end,
            clockReference: evaluation.clockReference
        )
        .visibleDeduplicatedByID()
        let daily = analyticsDomainStore.dailyBreakdown(
            segments: segments,
            range: .week,
            interval: interval,
            evaluatedAt: evaluation.cutoff,
            calendar: calendar
        )
        let requiresLiveRefresh = segments.contains { segment in
            guard segment.startedAt < interval.end else { return false }
            return segment.endedAt.map { $0 > evaluation.cutoff } ?? true
        }
        return WeeklyGrossTimeSnapshot(
            interval: interval,
            daily: daily,
            requiresLiveRefresh: requiresLiveRefresh
        )
    }
}
