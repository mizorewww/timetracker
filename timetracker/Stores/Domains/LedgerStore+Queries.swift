import Foundation

extension LedgerStore {
    var hasIndexedSegmentHistory: Bool {
        hasLoadedHistory
    }

    /// Returns only the indexed records that overlap the requested interval.
    /// Active records are included explicitly because they can cross into a
    /// new day after the day index was last rebuilt.
    func segments(overlapping interval: DateInterval, now: Date) -> [TimeSegment] {
        guard hasLoadedHistory else { return [] }
        let clockRewindIDs = now < segmentIndexEvaluationDate
            ? Set(segmentSnapshotByID.keys)
            : []
        let candidateIDs = segmentIDs(overlapping: [interval], now: now)
            .union(timeSensitiveSegmentIDs)
            .union(clockRewindIDs)
        return candidateIDs.compactMap { id in
            guard let segment = segmentByID[id], segment.deletedAt == nil else { return nil }
            guard TrackedTimePolicy.overlaps(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                interval: interval,
                now: now
            ) else {
                return nil
            }
            return segment
        }
    }
}
