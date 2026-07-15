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
        let candidateIDs = segmentIDs(overlapping: [interval], now: now)
            .union(activeSegmentIDs)
        return candidateIDs.compactMap { id in
            guard let segment = segmentByID[id], segment.deletedAt == nil else { return nil }
            let end = segment.endedAt ?? now
            guard segment.startedAt < interval.end, end > interval.start else { return nil }
            return segment
        }
    }
}
