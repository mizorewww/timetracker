import Foundation

nonisolated struct TodayTimelineSnapshotCacheKey: Equatable, Sendable {
    let analyticsRevision: UInt
    let taskReadModelRevision: UInt64
    let appleHealthReplicaRevision: Int
    let dayStart: Date
    let nowMinuteBucket: Int
}

nonisolated struct TodayTimelineSnapshotCache: Sendable {
    let key: TodayTimelineSnapshotCacheKey
    let snapshot: AnalyticsTimelineSnapshot
}

extension TimeTrackerStore {
    /// Minute bucket used by the Today timeline cache. The timeline clock
    /// already quantizes to whole minutes (the 60-second reference clock), so
    /// a same-minute cache hit reproduces exactly what a recompute would show.
    nonisolated static func timelineMinuteBucket(_ date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate / 60)
    }

    func timelineSnapshot(
        segments: [TimeSegment],
        date: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> AnalyticsTimelineSnapshot {
        // A sibling ModelContext can merge updated fields into the same
        // TimeSegment instances, leaving the segment array identity-equal.
        // Reading the value-semantic analytics revision gives Observation a
        // dependency that always advances after a visible ledger refresh.
        _ = analyticsRevision

        let dayInterval = calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(
                start: calendar.startOfDay(for: date),
                duration: 86400
            )
        let key = TodayTimelineSnapshotCacheKey(
            analyticsRevision: analyticsRevision,
            taskReadModelRevision: taskReadModelRevision,
            appleHealthReplicaRevision: appleHealthReplicaRevision,
            dayStart: dayInterval.start,
            nowMinuteBucket: Self.timelineMinuteBucket(now)
        )
        if let cached = todayTimelineSnapshotCache, cached.key == key {
            return cached.snapshot
        }

        let service = AnalyticsTimelineSnapshotService()
        let trackedSeeds = service.presentationSeeds(
            segments: segments,
            tasks: tasks,
            sessions: sessions,
            taskParentPathByID: taskParentPathByID,
            visibleInterval: dayInterval,
            now: now
        )
        let healthSeeds = appleHealthTimelineItems.map(timelinePresentationSeed)
        let snapshot = service.snapshot(
            seeds: trackedSeeds + healthSeeds,
            visibleInterval: dayInterval
        )
        todayTimelineSnapshotCache = TodayTimelineSnapshotCache(
            key: key,
            snapshot: snapshot
        )
        return snapshot
    }
}
