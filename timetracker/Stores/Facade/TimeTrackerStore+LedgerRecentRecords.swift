import Foundation

extension TimeTrackerStore {
    func visibleSegments(
        overlapping interval: DateInterval,
        taskIDs: Set<UUID>,
        evaluatedAt cutoff: Date,
        clockReference: Date
    ) -> [TimeSegment] {
        if ledgerDomainStore.hasIndexedSegmentHistory {
            return ledgerDomainStore.segments(
                overlapping: interval,
                taskIDs: taskIDs,
                evaluatedAt: cutoff,
                clockReference: clockReference
            )
            .filter(isReadableLedgerSegment)
        }
        return allSegments.filter { segment in
            guard segment.deletedAt == nil, taskIDs.contains(segment.taskID) else {
                return false
            }
            return TrackedTimePolicy.overlaps(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                interval: interval,
                now: cutoff
            )
        }
    }

    func visibleRecentSegments(
        forTaskIDs taskIDs: Set<UUID>,
        limit: Int = LedgerStore.maximumRecentSegmentsPerTask
    ) -> [TimeSegment] {
        guard limit > 0 else { return [] }
        if ledgerDomainStore.hasIndexedSegmentHistory {
            let indexed = ledgerDomainStore.recentSegments(forTaskIDs: taskIDs, limit: limit)
            let readable = indexed.filter(isReadableLedgerSegment)
            guard indexed.count == min(limit, LedgerStore.maximumRecentSegmentsPerTask),
                  readable.count < indexed.count
            else {
                return readable
            }
            return ledgerDomainStore.segments(forTaskIDs: taskIDs)
                .filter(isReadableLedgerSegment)
                .sorted {
                    if $0.startedAt != $1.startedAt {
                        return $0.startedAt > $1.startedAt
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }
                .prefix(limit)
                .map { $0 }
        }
        return allSegments.lazy
            .filter { $0.deletedAt == nil && taskIDs.contains($0.taskID) }
            .sorted {
                if $0.startedAt != $1.startedAt {
                    return $0.startedAt > $1.startedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .prefix(limit)
            .map { $0 }
    }
}
