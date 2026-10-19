import Foundation

extension TimeTrackerStore {
    /// `clockReference` is kept for API compatibility; range reads scan the
    /// ledger snapshots, so only `cutoff` affects the result.
    func visibleSegments(
        overlapping interval: DateInterval,
        taskIDs: Set<UUID>,
        evaluatedAt cutoff: Date,
        clockReference _: Date
    ) -> [TimeSegment] {
        ledgerDomainStore.segments(overlapping: interval, taskIDs: taskIDs, now: cutoff)
            .filter(isReadableLedgerSegment)
    }

    func visibleRecentSegments(
        forTaskIDs taskIDs: Set<UUID>,
        limit: Int = LedgerStore.maximumRecentSegmentsPerTask
    ) -> [TimeSegment] {
        guard limit > 0 else { return [] }
        return ledgerDomainStore.segments(forTaskIDs: taskIDs)
            .filter(isReadableLedgerSegment)
            .sorted {
                if $0.startedAt != $1.startedAt {
                    return $0.startedAt > $1.startedAt
                }
                return $0.id < $1.id
            }
            .prefix(limit)
            .map { $0 }
    }
}
