import Foundation

struct LedgerStore {
    private(set) var activeSegments: [TimeSegment] = []
    private(set) var todaySegments: [TimeSegment] = []
    var allSegments: [TimeSegment] = []
    var rollupChanges: [LedgerSegmentChange] = []

    var sessions: [TimeSession] { sessionIndex.sessions }

    var segmentByID: [UUID: TimeSegment] = [:]
    var segmentSnapshotByID: [UUID: LedgerSegmentSnapshot] = [:]
    var segmentArrayIndexByID: [UUID: Int] = [:]
    var segmentIDsByDay: [Date: Set<UUID>] = [:]
    var segmentIDsByTaskID: [UUID: Set<UUID>] = [:]
    var segmentIDsBySessionID: [UUID: Set<UUID>] = [:]
    var activeSegmentIDs: Set<UUID> = []
    var timeSensitiveSegmentIDs: Set<UUID> = []
    var pendingRollupChangeByID: [UUID: LedgerSegmentChange] = [:]
    var segmentIndexEvaluationDate = Date.distantPast
    var segmentIndexCalendar = Calendar.current
    private(set) var hasLoadedHistory = false
    private var sessionIndex = LedgerSessionIndex()

    mutating func refresh(repository: TimeTrackingRepository, now: Date = Date(), calendar: Calendar = .current) throws {
        activeSegments = try repository.activeSegments().deduplicatedByID()
        let today = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 24 * 60 * 60)
        todaySegments = try repository.segments(from: today.start, to: today.end, now: now).deduplicatedByID()
        try refreshHistory(repository: repository, now: now, calendar: calendar)
    }

    mutating func refreshVisible(repository: TimeTrackingRepository, now: Date = Date(), calendar: Calendar = .current) throws {
        let refreshedActive = try repository.activeSegments().deduplicatedByID()
        let today = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 24 * 60 * 60)
        let refreshedToday = try repository.segments(from: today.start, to: today.end, now: now).deduplicatedByID()
        if segmentIndexEvaluationDate != .distantPast, segmentIndexCalendar != calendar {
            rebuildSegmentDayIndex(now: now, calendar: calendar)
        }
        let visibleFetched = uniqueSegments(refreshedActive + refreshedToday)
        let impactedIDs = segmentIDs(overlapping: [today], now: now)
            .union(activeSegmentIDs)
            .union(visibleFetched.map(\.id))
        // A previously active segment can close outside today's interval (for
        // example, startup reconciliation just after midnight). Re-fetch every
        // impacted identity so the full-history index receives that terminal
        // version instead of retaining the old active object or deleting it.
        let fetched = uniqueSegments(
            visibleFetched + (try repository.segments(ids: impactedIDs))
        )
        let impactedSessionIDs = Set(
            impactedIDs.compactMap { segmentSnapshotByID[$0]?.sessionID }
        ).union(fetched.map(\.sessionID))

        replaceSegments(
            ids: impactedIDs,
            with: fetched,
            now: now,
            calendar: calendar,
            refreshUnchangedTimeSensitiveSegments: true
        )
        if impactedSessionIDs.isEmpty == false {
            sessionIndex.replace(
                ids: impactedSessionIDs,
                with: try repository.sessions(ids: impactedSessionIDs)
            )
        }
        activeSegments = refreshedActive
        todaySegments = refreshedToday
    }

    mutating func refreshHistory(
        repository: TimeTrackingRepository,
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws {
        let fetchedSegments = try repository.allSegments().deduplicatedByID()
        rebuildSegmentIndexes(segments: fetchedSegments, now: now, calendar: calendar)
        sessionIndex.rebuild(try repository.sessions())
        hasLoadedHistory = true
        resetRollupChanges()
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
            try refreshHistory(repository: repository, now: now)
            return
        }

        guard hasLoadedHistory else {
            try refreshHistory(repository: repository, now: now)
            return
        }

        let newlyOverlappingTimeSensitiveIDs = timeSensitiveSegmentIDs.filter { id in
            guard let snapshot = segmentSnapshotByID[id] else { return false }
            return intervals.contains { snapshot.overlaps($0, at: now) }
        }
        let existingImpactedIDs = segmentIDs(overlapping: intervals, now: now)
            .union(newlyOverlappingTimeSensitiveIDs)
        let existingImpactedSnapshots = existingImpactedIDs.compactMap { segmentSnapshotByID[$0] }

        var fetchedSegments: [TimeSegment] = []
        for interval in intervals {
            fetchedSegments += try repository.segments(from: interval.start, to: interval.end, now: now)
        }
        fetchedSegments = uniqueSegments(fetchedSegments).deduplicatedByID()

        let impactedSessionIDs = Set(existingImpactedSnapshots.map(\.sessionID))
            .union(fetchedSegments.map(\.sessionID))
        replaceSegments(
            ids: existingImpactedIDs.union(fetchedSegments.map(\.id)),
            with: fetchedSegments,
            now: now,
            calendar: segmentIndexCalendar,
            refreshUnchangedTimeSensitiveSegments: true
        )

        if impactedSessionIDs.isEmpty == false {
            let refreshedSessions = try repository.sessions(ids: impactedSessionIDs).deduplicatedByID()
            sessionIndex.replace(ids: impactedSessionIDs, with: refreshedSessions)
        }
    }

    mutating func resetRollupChanges() {
        pendingRollupChangeByID.removeAll(keepingCapacity: true)
        rollupChanges.removeAll(keepingCapacity: true)
    }

    func segment(for id: UUID) -> TimeSegment? {
        segmentByID[id]
    }

    func session(for id: UUID) -> TimeSession? {
        sessionIndex.session(for: id)
    }

    func sessions(for ids: Set<UUID>) -> [TimeSession] {
        sessionIndex.sessions(for: ids)
    }

}
