import Foundation

/// Today's page read model: everything the Today page derives from the
/// store, produced once per data revision (and per minute for the
/// clock-dependent half) instead of in view bodies.
struct TodaySnapshot {
    let content: TodayHomeContent
    let live: TodayLiveSnapshot
}

/// The clock-dependent half of Today: totals and the timeline.
struct TodayLiveSnapshot {
    let metrics: TodayMetricsSnapshot
    let timeline: AnalyticsTimelineSnapshot
    /// Timeline entries newest first, for the rows under the chart.
    let rows: [AnalyticsTimelineEntry]
    let segmentByID: [UUID: TimeSegment]
    /// A timer is running or a today segment ends in the future, so the
    /// page changes every minute.
    let isLive: Bool
}

/// The single owner of Today's cached read model. Each half is keyed by
/// every store value it reads; the store never publishes when it fills it.
struct TodayReadModelCache {
    fileprivate struct ContentKey: Equatable {
        let analyticsRevision: UInt
        let taskReadModelRevision: UInt64
        let selectedTaskID: UUID?
        let quickStartTaskIDs: [UUID]
        let countdownEventIDs: [UUID]
        let quickStartLimit: Int
        let forecastLimit: Int
    }

    fileprivate struct LiveKey: Equatable {
        let analyticsRevision: UInt
        let taskReadModelRevision: UInt64
        let dayStart: Date
        let minuteBucket: Int
    }

    fileprivate struct WeeklyKey: Equatable {
        let analyticsRevision: UInt
        let weekStart: Date
        let minuteBucket: Int
    }

    fileprivate var content: (key: ContentKey, value: TodayHomeContent)?
    fileprivate var live: (key: LiveKey, value: TodayLiveSnapshot)?
    fileprivate var weekly: (key: WeeklyKey, value: WeeklyGrossTimeSnapshot)?
}

extension TimeTrackerStore {
    /// Today's read model at `now`.
    ///
    /// Tab switches and every clock tick re-evaluate the page body; a call
    /// only compares the cache keys (a few revision reads + UUID arrays),
    /// which also registers the Observation dependencies that refresh the
    /// page after a ledger, task, or preference change. A same-minute hit
    /// reproduces what a recompute would show: the page clock is
    /// minute-granular, and every visible write bumps a revision.
    func todaySnapshot(
        now: Date,
        quickStartLimit: Int = 4,
        forecastLimit: Int = 3,
        calendar: Calendar = .current
    ) -> TodaySnapshot {
        TodaySnapshot(
            content: todayContent(quickStartLimit: quickStartLimit, forecastLimit: forecastLimit),
            live: todayLive(now: now, calendar: calendar)
        )
    }

    private func todayContent(quickStartLimit: Int, forecastLimit: Int) -> TodayHomeContent {
        let key = TodayReadModelCache.ContentKey(
            analyticsRevision: analyticsRevision,
            taskReadModelRevision: taskReadModelRevision,
            selectedTaskID: selectedTaskID,
            quickStartTaskIDs: preferences.quickStartTaskIDs,
            countdownEventIDs: countdownEvents.map(\.id),
            quickStartLimit: quickStartLimit,
            forecastLimit: forecastLimit
        )
        if let cached = todayReadModelCache.content, cached.key == key {
            return cached.value
        }
        let content = TodayHomeContent(
            store: self,
            quickStartLimit: quickStartLimit,
            forecastLimit: forecastLimit
        )
        todayReadModelCache.content = (key, content)
        return content
    }

    private func todayLive(now: Date, calendar: Calendar) -> TodayLiveSnapshot {
        let dayInterval = calendar.dateInterval(of: .day, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 86400)
        let key = TodayReadModelCache.LiveKey(
            analyticsRevision: analyticsRevision,
            taskReadModelRevision: taskReadModelRevision,
            dayStart: dayInterval.start,
            minuteBucket: Int(now.timeIntervalSinceReferenceDate / 60)
        )
        if let cached = todayReadModelCache.live, cached.key == key {
            return cached.value
        }

        let segments = timelineSegments
        let service = AnalyticsTimelineSnapshotService()
        let timeline = service.snapshot(
            seeds: service.presentationSeeds(
                segments: segments,
                tasks: tasks,
                sessions: sessions,
                taskParentPathByID: taskParentPathByID,
                visibleInterval: dayInterval,
                now: now
            ),
            visibleInterval: dayInterval
        )
        let live = TodayLiveSnapshot(
            metrics: todayMetrics(now: now, calendar: calendar),
            timeline: timeline,
            rows: timeline.entries.reversed(),
            segmentByID: segments.latestByID(),
            isLive: activeSegments.isEmpty == false || segments.contains { segment in
                segment.endedAt.map { $0 > now } ?? true
            }
        )
        todayReadModelCache.live = (key, live)
        return live
    }

    private func todayMetrics(
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

        func wallSeconds(for intervals: [DateInterval]) -> Int {
            TimeAggregationService.mergeOverlappingIntervals(intervals).reduce(0) {
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
        // Same minute-granular contract as `todayLive`.
        let key = TodayReadModelCache.WeeklyKey(
            analyticsRevision: analyticsRevision,
            weekStart: interval.start,
            minuteBucket: Int(now.timeIntervalSinceReferenceDate / 60)
        )
        if let cached = todayReadModelCache.weekly, cached.key == key {
            return cached.value
        }

        let segments = visibleSegments(
            overlapping: interval,
            now: interval.end
        )
        let daily = analyticsDomainStore.dailyBreakdown(
            segments: AnalyticsSegmentRecord.records(segments),
            range: .week,
            interval: interval,
            evaluatedAt: evaluation.cutoff,
            calendar: calendar
        )
        let requiresLiveRefresh = segments.contains { segment in
            guard segment.startedAt < interval.end else { return false }
            return segment.endedAt.map { $0 > evaluation.cutoff } ?? true
        }
        let snapshot = WeeklyGrossTimeSnapshot(
            interval: interval,
            daily: daily,
            requiresLiveRefresh: requiresLiveRefresh
        )
        todayReadModelCache.weekly = (key, snapshot)
        return snapshot
    }
}
