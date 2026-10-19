import Foundation

extension LedgerStore {
    nonisolated static let maximumRecentSegmentsPerTask = 8

    /// Returns the indexed records that overlap the requested interval, with
    /// open and future-ended records clipped at `now`. Before the first full
    /// history load the index holds only the visible (today/active) window.
    func segments(overlapping interval: DateInterval, now: Date) -> [TimeSegment] {
        models(for: segmentSnapshotByID.values.lazy.filter {
            $0.overlaps(interval, at: now)
        }.map(\.id))
    }

    func segments(
        overlapping interval: DateInterval,
        taskIDs: Set<UUID>,
        now: Date
    ) -> [TimeSegment] {
        models(for: segmentIDs(forTaskIDs: taskIDs).filter { id in
            segmentSnapshotByID[id]?.overlaps(interval, at: now) == true
        })
    }

    func segments(forTaskIDs taskIDs: Set<UUID>) -> [TimeSegment] {
        models(for: segmentIDs(forTaskIDs: taskIDs))
    }

    func snapshots(forTaskID taskID: UUID) -> [LedgerSegmentSnapshot] {
        (segmentIDsByTaskID[taskID] ?? []).compactMap { segmentSnapshotByID[$0] }
    }

    private func segmentIDs(forTaskIDs taskIDs: Set<UUID>) -> Set<UUID> {
        taskIDs.reduce(into: Set<UUID>()) { result, taskID in
            result.formUnion(segmentIDsByTaskID[taskID] ?? [])
        }
    }

    /// Snapshots carry the indexed values; the live model still decides
    /// visibility so an in-context soft delete hides the row immediately.
    private func models(for ids: some Sequence<UUID>) -> [TimeSegment] {
        ids.compactMap { id in
            guard let segment = segmentByID[id], segment.deletedAt == nil else { return nil }
            return segment
        }
    }
}
