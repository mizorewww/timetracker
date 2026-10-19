import Foundation

/// Segment and session identities whose relationship visibility (AD-036) may
/// have changed since the facade last derived it.
struct LedgerRelationshipChanges {
    var requiresFullRebuild = true
    var segmentIDs = Set<UUID>()
    var sessionIDs = Set<UUID>()
}

/// In-memory ledger read model: every visible segment keyed by ID plus a
/// per-task bucket. Range reads scan the immutable value snapshots, which keeps
/// open and future-ended records correct without any day-bucket bookkeeping.
struct LedgerStore {
    private(set) var activeSegments: [TimeSegment] = []
    private(set) var todaySegments: [TimeSegment] = []
    var rollupChanges: [LedgerSegmentChange] = []

    var sessions: [TimeSession] {
        sessionIndex.sessions
    }

    private(set) var segmentByID: [UUID: TimeSegment] = [:]
    /// Value copies of `segmentByID`: SwiftData edits models in place, so the
    /// snapshot is the "before" value for rollup deltas and the cheap
    /// field source for range scans.
    private(set) var segmentSnapshotByID: [UUID: LedgerSegmentSnapshot] = [:]
    private(set) var segmentIDsByTaskID: [UUID: Set<UUID>] = [:]
    private var segmentIDsBySessionID: [UUID: Set<UUID>] = [:]
    private var pendingRollupChangeByID: [UUID: LedgerSegmentChange] = [:]
    private var relationshipChanges = LedgerRelationshipChanges()
    private(set) var hasLoadedHistory = false
    private var sessionIndex = LedgerSessionIndex()
    /// Segments that are open or ended after `recentWindowStart` (the start of
    /// the last visible day), so a visible refresh re-reads only this small
    /// set instead of scanning the whole history for leavers.
    private var recentSegmentIDs = Set<UUID>()
    private var recentWindowStart = Date.distantPast

    mutating func refresh(repository: SwiftDataTimeTrackingRepository, now: Date = Date(), calendar: Calendar = .current) throws {
        activeSegments = try repository.activeSegments()
        let today = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 24 * 60 * 60)
        todaySegments = try repository.segments(from: today.start, to: today.end, now: now)
        recentWindowStart = today.start
        try refreshHistory(repository: repository)
    }

    mutating func refreshVisible(repository: SwiftDataTimeTrackingRepository, now: Date = Date(), calendar: Calendar = .current) throws {
        let refreshedActive = try repository.activeSegments()
        let today = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 24 * 60 * 60)
        let refreshedToday = try repository.segments(from: today.start, to: today.end, now: now)
        let visibleFetched = uniqueSegments(refreshedActive + refreshedToday)
        moveRecentWindow(to: today.start)
        // A previously active segment can close outside today's interval (for
        // example, startup reconciliation just after midnight). Re-fetch every
        // impacted identity so the index receives that terminal version
        // instead of retaining the old active object or deleting it.
        let impactedIDs = recentSegmentIDs.union(visibleFetched.map(\.id))
        let fetched = try uniqueSegments(
            visibleFetched + (repository.segments(ids: impactedIDs))
        )
        let impactedSessionIDs = Set(
            impactedIDs.compactMap { segmentSnapshotByID[$0]?.sessionID }
        ).union(fetched.map(\.sessionID))

        replaceSegments(ids: impactedIDs, with: fetched, now: now)
        if impactedSessionIDs.isEmpty == false {
            try relationshipChanges.sessionIDs.formUnion(sessionIndex.replace(
                ids: impactedSessionIDs,
                with: repository.sessions(ids: impactedSessionIDs)
            ))
        }
        activeSegments = refreshedActive
        todaySegments = refreshedToday
    }

    private mutating func refreshHistory(repository: SwiftDataTimeTrackingRepository) throws {
        try rebuildSegmentIndexes(segments: repository.allSegments())
        try sessionIndex.rebuild(repository.sessions())
        relationshipChanges = LedgerRelationshipChanges()
        hasLoadedHistory = true
        resetRollupChanges()
    }

    mutating func refreshHistoryRanges(
        repository: SwiftDataTimeTrackingRepository,
        ranges: [StoreInvalidationRange],
        now: Date = Date()
    ) throws {
        let intervals = ranges.compactMap { range -> DateInterval? in
            guard range.end > range.start else { return nil }
            return DateInterval(start: range.start, end: range.end)
        }
        guard intervals.isEmpty == false, hasLoadedHistory else {
            try refreshHistory(repository: repository)
            return
        }

        let existingImpactedSnapshots = segmentSnapshotByID.values.filter { snapshot in
            intervals.contains { snapshot.overlaps($0, at: now) }
        }
        var fetchedSegments: [TimeSegment] = []
        for interval in intervals {
            fetchedSegments += try repository.segments(from: interval.start, to: interval.end, now: now)
        }
        fetchedSegments = uniqueSegments(fetchedSegments)

        let impactedSessionIDs = Set(existingImpactedSnapshots.map(\.sessionID))
            .union(fetchedSegments.map(\.sessionID))
        replaceSegments(
            ids: Set(existingImpactedSnapshots.map(\.id)).union(fetchedSegments.map(\.id)),
            with: fetchedSegments,
            now: now
        )

        if impactedSessionIDs.isEmpty == false {
            let refreshedSessions = try repository.sessions(ids: impactedSessionIDs)
            relationshipChanges.sessionIDs.formUnion(
                sessionIndex.replace(ids: impactedSessionIDs, with: refreshedSessions)
            )
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

    func segmentIDs(forSessionIDs sessionIDs: Set<UUID>) -> Set<UUID> {
        sessionIDs.reduce(into: Set<UUID>()) { result, sessionID in
            result.formUnion(segmentIDsBySessionID[sessionID] ?? [])
        }
    }

    /// Returns the relationship changes since the previous call and starts a
    /// new accumulation window.
    mutating func takeRelationshipChanges() -> LedgerRelationshipChanges {
        defer {
            relationshipChanges = LedgerRelationshipChanges(requiresFullRebuild: false)
        }
        return relationshipChanges
    }

    private static func isRecent(_ snapshot: LedgerSegmentSnapshot, windowStart: Date) -> Bool {
        snapshot.endedAt.map { $0 > windowStart } ?? true
    }

    private mutating func moveRecentWindow(to windowStart: Date) {
        guard windowStart != recentWindowStart else { return }
        let movedForward = windowStart > recentWindowStart
        recentWindowStart = windowStart
        // Moving forward only drops members; a backward clock change must
        // rescan the index for segments the narrower window had excluded.
        let candidates = movedForward
            ? recentSegmentIDs.compactMap { segmentSnapshotByID[$0] }
            : Array(segmentSnapshotByID.values)
        recentSegmentIDs = Set(
            candidates.filter { Self.isRecent($0, windowStart: windowStart) }.map(\.id)
        )
    }

    private mutating func rebuildSegmentIndexes(segments: [TimeSegment]) {
        // The repository already resolves LWW and hides tombstones.
        segmentByID = segments.reduce(into: [:]) { $0[$1.id] = $1 }
        segmentSnapshotByID = segmentByID.mapValues(LedgerSegmentSnapshot.init)
        segmentIDsByTaskID = Dictionary(grouping: segmentSnapshotByID.values, by: \.taskID)
            .mapValues { Set($0.map(\.id)) }
        segmentIDsBySessionID = Dictionary(grouping: segmentSnapshotByID.values, by: \.sessionID)
            .mapValues { Set($0.map(\.id)) }
        let windowStart = recentWindowStart
        recentSegmentIDs = Set(
            segmentSnapshotByID.values
                .filter { Self.isRecent($0, windowStart: windowStart) }
                .map(\.id)
        )
    }

    private mutating func replaceSegments(
        ids: Set<UUID>,
        with fetchedSegments: [TimeSegment],
        now: Date
    ) {
        let fetchedByID = fetchedSegments.reduce(into: [UUID: TimeSegment]()) {
            $0[$1.id] = $1
        }

        for id in ids {
            let before = segmentSnapshotByID[id]
            let afterModel = fetchedByID[id]
            let after = afterModel.map(LedgerSegmentSnapshot.init)
            // Running and future-ended records are re-reported even when
            // unchanged so the rollup re-evaluates their elapsed time.
            if before != after || after?.isTimeSensitive(at: now) == true {
                recordRollupChange(id: id, before: before, after: after)
            }
            if before != after || segmentByID[id] !== afterModel {
                relationshipChanges.segmentIDs.insert(id)
            }

            if let before, before.taskID != after?.taskID {
                segmentIDsByTaskID[before.taskID]?.remove(id)
                if segmentIDsByTaskID[before.taskID]?.isEmpty == true {
                    segmentIDsByTaskID.removeValue(forKey: before.taskID)
                }
            }
            if let before, before.sessionID != after?.sessionID {
                segmentIDsBySessionID[before.sessionID]?.remove(id)
                if segmentIDsBySessionID[before.sessionID]?.isEmpty == true {
                    segmentIDsBySessionID.removeValue(forKey: before.sessionID)
                }
            }
            if let afterModel, let after {
                segmentByID[id] = afterModel
                segmentSnapshotByID[id] = after
                segmentIDsByTaskID[after.taskID, default: []].insert(id)
                segmentIDsBySessionID[after.sessionID, default: []].insert(id)
            } else {
                segmentByID.removeValue(forKey: id)
                segmentSnapshotByID.removeValue(forKey: id)
            }
            if let after, Self.isRecent(after, windowStart: recentWindowStart) {
                recentSegmentIDs.insert(id)
            } else {
                recentSegmentIDs.remove(id)
            }
        }

        rollupChanges = pendingRollupChangeByID.values.sorted {
            $0.id < $1.id
        }
    }

    private mutating func recordRollupChange(
        id: UUID,
        before: LedgerSegmentSnapshot?,
        after: LedgerSegmentSnapshot?
    ) {
        // Coalesced changes keep the first-seen "before" (nil for inserts).
        let firstBefore = pendingRollupChangeByID[id].map(\.before) ?? before
        pendingRollupChangeByID[id] = LedgerSegmentChange(id: id, before: firstBefore, after: after)
    }

    private func uniqueSegments(_ segments: [TimeSegment]) -> [TimeSegment] {
        segments.deduplicatedByID().filter { $0.deletedAt == nil }
    }
}
