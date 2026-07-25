import Foundation

extension TimeTrackerStore {
    func timelineSnapshot(
        segments: [TimeSegment],
        date: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> AnalyticsTimelineSnapshot {
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
