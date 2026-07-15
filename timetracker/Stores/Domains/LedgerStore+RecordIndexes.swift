import Foundation

extension LedgerStore {
    mutating func rebuildRecordIndexes() {
        segmentIDsByTaskID = Dictionary(grouping: segmentSnapshotByID.values, by: \.taskID)
            .mapValues { Set($0.map(\.id)) }
        segmentIDsBySessionID = Dictionary(grouping: segmentSnapshotByID.values, by: \.sessionID)
            .mapValues { Set($0.map(\.id)) }
    }

    mutating func indexRecord(_ snapshot: LedgerSegmentSnapshot) {
        segmentIDsByTaskID[snapshot.taskID, default: []].insert(snapshot.id)
        segmentIDsBySessionID[snapshot.sessionID, default: []].insert(snapshot.id)
    }

    mutating func unindexRecord(_ snapshot: LedgerSegmentSnapshot) {
        Self.remove(snapshot.id, from: snapshot.taskID, in: &segmentIDsByTaskID)
        Self.remove(snapshot.id, from: snapshot.sessionID, in: &segmentIDsBySessionID)
    }

    func segments(forTaskIDs taskIDs: Set<UUID>) -> [TimeSegment] {
        taskIDs.reduce(into: Set<UUID>()) { result, taskID in
            result.formUnion(segmentIDsByTaskID[taskID] ?? [])
        }.compactMap { segmentByID[$0] }
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
}
