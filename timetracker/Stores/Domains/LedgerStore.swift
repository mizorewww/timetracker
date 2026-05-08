import Foundation

struct LedgerStore {
    private(set) var activeSegments: [TimeSegment] = []
    private(set) var pausedSessions: [TimeSession] = []
    private(set) var todaySegments: [TimeSegment] = []
    private(set) var allSegments: [TimeSegment] = []
    private(set) var sessions: [TimeSession] = []

    mutating func refresh(repository: TimeTrackingRepository, now: Date = Date(), calendar: Calendar = .current) throws {
        try refreshVisible(repository: repository, now: now, calendar: calendar)
        try refreshHistory(repository: repository)
    }

    mutating func refreshVisible(repository: TimeTrackingRepository, now: Date = Date(), calendar: Calendar = .current) throws {
        activeSegments = try repository.activeSegments()
        pausedSessions = try repository.pausedSessions()

        let today = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 24 * 60 * 60)
        todaySegments = try repository.segments(from: today.start, to: today.end, now: now)
        mergeVisibleSegments(todayInterval: today, now: now)
    }

    mutating func refreshHistory(repository: TimeTrackingRepository) throws {
        allSegments = try repository.allSegments()
        sessions = try repository.sessions()
    }

    mutating func refreshHistoryRanges(
        repository: TimeTrackingRepository,
        ranges: [StoreInvalidationRange],
        now: Date = Date()
    ) throws {
        let intervals = ranges.compactMap { range -> DateInterval? in
            guard range.end > range.start else { return nil }
            return DateInterval(start: range.start, end: range.end)
        }
        guard intervals.isEmpty == false else {
            try refreshHistory(repository: repository)
            return
        }

        guard allSegments.isEmpty == false || sessions.isEmpty == false else {
            try refreshHistory(repository: repository)
            return
        }

        let existingImpactedSegments = allSegments.filter { segment in
            intervals.contains { overlaps(segment, with: $0, now: now) }
        }

        var fetchedSegments: [TimeSegment] = []
        for interval in intervals {
            fetchedSegments += try repository.segments(from: interval.start, to: interval.end, now: now)
        }
        fetchedSegments = uniqueSegments(fetchedSegments)

        let impactedSessionIDs = Set(existingImpactedSegments.map(\.sessionID))
            .union(fetchedSegments.map(\.sessionID))
        let fetchedSegmentIDs = Set(fetchedSegments.map(\.id))

        allSegments = allSegments.filter { segment in
            let wasFetched = fetchedSegmentIDs.contains(segment.id)
            let isInAffectedRange = intervals.contains { overlaps(segment, with: $0, now: now) }
            return wasFetched == false && isInAffectedRange == false
        } + fetchedSegments
        allSegments.sort { $0.startedAt < $1.startedAt }

        if impactedSessionIDs.isEmpty == false {
            let refreshedSessions = try repository.sessions(ids: impactedSessionIDs)
            sessions = sessions.filter { impactedSessionIDs.contains($0.id) == false } + refreshedSessions
            sessions.sort { $0.startedAt > $1.startedAt }
        }
    }

    private mutating func mergeVisibleSegments(todayInterval: DateInterval, now: Date) {
        guard !allSegments.isEmpty else {
            allSegments = todaySegments
            return
        }

        let visibleIDs = Set(todaySegments.map(\.id))
        allSegments = allSegments
            .filter { segment in
                if visibleIDs.contains(segment.id) {
                    return false
                }
                let end = segment.endedAt ?? now
                return !(segment.startedAt < todayInterval.end && end > todayInterval.start)
            } + todaySegments
        allSegments.sort { $0.startedAt < $1.startedAt }
    }

    private func overlaps(_ segment: TimeSegment, with interval: DateInterval, now: Date) -> Bool {
        let end = min(segment.endedAt ?? now, interval.end)
        return segment.startedAt < interval.end && end > interval.start
    }

    private func uniqueSegments(_ segments: [TimeSegment]) -> [TimeSegment] {
        var seen = Set<UUID>()
        return segments.filter { segment in
            seen.insert(segment.id).inserted
        }
    }
}
