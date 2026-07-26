import Foundation

extension TimeTrackerStore {
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
        return service.snapshot(
            seeds: trackedSeeds + healthSeeds,
            visibleInterval: dayInterval
        )
    }
}
