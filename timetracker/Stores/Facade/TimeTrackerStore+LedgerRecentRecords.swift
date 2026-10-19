import Foundation

extension TimeTrackerStore {
    func visibleSegments(
        overlapping interval: DateInterval,
        taskIDs: Set<UUID>,
        now: Date
    ) -> [TimeSegment] {
        ledgerDomainStore.segments(overlapping: interval, taskIDs: taskIDs, now: now)
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
