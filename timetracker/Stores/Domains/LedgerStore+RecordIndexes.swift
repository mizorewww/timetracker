import Foundation

extension LedgerStore {
    nonisolated static let maximumRecentSegmentsPerTask = 8

    mutating func rebuildRecordIndexes() {
        segmentIDsByTaskID = Dictionary(grouping: segmentSnapshotByID.values, by: \.taskID)
            .mapValues { Set($0.map(\.id)) }
        recentSegmentIDsByTaskID = Dictionary(grouping: segmentSnapshotByID.values, by: \.taskID)
            .mapValues { snapshots in
                snapshots.sorted(by: Self.isMoreRecent).prefix(Self.maximumRecentSegmentsPerTask).map(\.id)
            }
        segmentIDsBySessionID = Dictionary(grouping: segmentSnapshotByID.values, by: \.sessionID)
            .mapValues { Set($0.map(\.id)) }
    }

    mutating func indexRecord(_ snapshot: LedgerSegmentSnapshot) {
        segmentIDsByTaskID[snapshot.taskID, default: []].insert(snapshot.id)
        var recentSnapshots = (recentSegmentIDsByTaskID[snapshot.taskID] ?? []).compactMap { id in
            id == snapshot.id ? snapshot : segmentSnapshotByID[id]
        }
        if recentSnapshots.contains(where: { $0.id == snapshot.id }) == false {
            recentSnapshots.append(snapshot)
        }
        recentSegmentIDsByTaskID[snapshot.taskID] = recentSnapshots
            .sorted(by: Self.isMoreRecent)
            .prefix(Self.maximumRecentSegmentsPerTask)
            .map(\.id)
        segmentIDsBySessionID[snapshot.sessionID, default: []].insert(snapshot.id)
    }

    mutating func unindexRecord(_ snapshot: LedgerSegmentSnapshot) {
        Self.remove(snapshot.id, from: snapshot.taskID, in: &segmentIDsByTaskID)
        rebuildRecentRecordIndex(for: snapshot.taskID)
        Self.remove(snapshot.id, from: snapshot.sessionID, in: &segmentIDsBySessionID)
    }

    func segments(forTaskIDs taskIDs: Set<UUID>) -> [TimeSegment] {
        taskIDs.reduce(into: Set<UUID>()) { result, taskID in
            result.formUnion(segmentIDsByTaskID[taskID] ?? [])
        }.compactMap { segmentByID[$0] }
    }

    func recentSegments(
        forTaskIDs taskIDs: Set<UUID>,
        limit: Int = Self.maximumRecentSegmentsPerTask
    ) -> [TimeSegment] {
        guard limit > 0 else { return [] }
        let boundedLimit = min(limit, Self.maximumRecentSegmentsPerTask)
        let candidateIDs = taskIDs.reduce(into: Set<UUID>()) { result, taskID in
            result.formUnion(recentSegmentIDsByTaskID[taskID] ?? [])
        }
        return candidateIDs.compactMap { segmentByID[$0] }
            .sorted(by: Self.isMoreRecent)
            .prefix(boundedLimit)
            .map { $0 }
    }

    func segments(forSessionID sessionID: UUID) -> [TimeSegment] {
        (segmentIDsBySessionID[sessionID] ?? []).compactMap { segmentByID[$0] }
    }

    private static func remove(
        _ segmentID: UUID,
        from ownerID: UUID,
        in index: inout [UUID: Set<UUID>]
    ) {
        index[ownerID]?.remove(segmentID)
        if index[ownerID]?.isEmpty == true {
            index.removeValue(forKey: ownerID)
        }
    }

    private mutating func rebuildRecentRecordIndex(for taskID: UUID) {
        let snapshots = (segmentIDsByTaskID[taskID] ?? []).compactMap { segmentSnapshotByID[$0] }
        guard snapshots.isEmpty == false else {
            recentSegmentIDsByTaskID.removeValue(forKey: taskID)
            return
        }
        recentSegmentIDsByTaskID[taskID] = snapshots
            .sorted(by: Self.isMoreRecent)
            .prefix(Self.maximumRecentSegmentsPerTask)
            .map(\.id)
    }

    nonisolated private static func isMoreRecent(
        _ lhs: LedgerSegmentSnapshot,
        _ rhs: LedgerSegmentSnapshot
    ) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt > rhs.startedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    nonisolated private static func isMoreRecent(_ lhs: TimeSegment, _ rhs: TimeSegment) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt > rhs.startedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
