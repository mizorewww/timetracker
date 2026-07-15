import Foundation

extension LedgerStore {
    var hasIndexedSegmentHistory: Bool {
        hasLoadedHistory
    }

    /// Returns only the indexed records that overlap the requested interval.
    /// Active records are included explicitly because they can cross into a
    /// new day after the day index was last rebuilt.
    func segments(overlapping interval: DateInterval, now: Date) -> [TimeSegment] {
        segments(
            overlapping: interval,
            evaluatedAt: now,
            clockReference: now
        )
    }

    /// `evaluatedAt` clips open and future-ended records for the requested
    /// read model. `clockReference` is kept separate so a historical cutoff is
    /// not mistaken for a real backward system-clock correction.
    func segments(
        overlapping interval: DateInterval,
        evaluatedAt cutoff: Date,
        clockReference: Date
    ) -> [TimeSegment] {
        guard hasLoadedHistory else { return [] }
        let candidateIDs = segmentCandidateIDs(
            overlapping: interval,
            evaluatedAt: cutoff,
            clockReference: clockReference
        )
        return candidateIDs.compactMap { id in
            guard let segment = segmentByID[id], segment.deletedAt == nil else { return nil }
            guard TrackedTimePolicy.overlaps(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                interval: interval,
                now: cutoff
            ) else {
                return nil
            }
            return segment
        }
    }

    /// Internal diagnostic boundary shared with performance-focused tests.
    /// Only a genuine wall-clock rewind expands a query to the full ledger.
    func segmentCandidateIDs(
        overlapping interval: DateInterval,
        evaluatedAt cutoff: Date,
        clockReference: Date
    ) -> Set<UUID> {
        let clockRewindIDs = clockReference < segmentIndexEvaluationDate
            ? Set(segmentSnapshotByID.keys)
            : []
        return segmentIDs(overlapping: [interval], now: cutoff)
            .union(timeSensitiveSegmentIDs)
            .union(clockRewindIDs)
    }
}
