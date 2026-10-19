import Foundation
import SwiftData

extension TimeTrackerStore {
    /// Above this many changed segments a full re-derivation is cheaper than
    /// patching the sorted array one insertion at a time.
    private static let incrementalVisibilityLimit = 256

    /// Re-reads which task rows exist, tombstones included. Task refreshes
    /// rebuild it; a ledger refresh re-reads it only when a changed row
    /// references a task ID it has not seen (for example a task inserted by
    /// another writer).
    func refreshExistingTaskIDs() throws {
        guard let modelContext else {
            existingTaskIDs = []
            return
        }
        var descriptor = FetchDescriptor<TaskNode>()
        descriptor.propertiesToFetch = [\.id]
        existingTaskIDs = try Set(modelContext.fetch(descriptor).map(\.id))
    }

    /// Keeps temporarily incomplete CloudKit relationship graphs in SwiftData
    /// without publishing them to totals or system surfaces. A later refresh
    /// makes the rows visible as soon as their parent records arrive.
    func refreshLedgerRelationshipVisibility() throws {
        let changes = ledgerDomainStore.takeRelationshipChanges()
        let affectedSegmentIDs = changes.segmentIDs.union(
            ledgerDomainStore.segmentIDs(forSessionIDs: changes.sessionIDs)
        )
        let referencesUnknownTask = changes.requiresFullRebuild
            ? ledgerDomainStore.sessions.contains { existingTaskIDs.contains($0.taskID) == false }
            : ledgerDomainStore.sessions(for: changes.sessionIDs).contains {
                existingTaskIDs.contains($0.taskID) == false
            } || affectedSegmentIDs.contains { id in
                ledgerDomainStore.segmentSnapshotByID[id].map {
                    existingTaskIDs.contains($0.taskID) == false
                } ?? false
            }
        if referencesUnknownTask {
            try refreshExistingTaskIDs()
        }

        if changes.requiresFullRebuild ||
            ledgerVisibilityExistingTaskIDs != existingTaskIDs ||
            affectedSegmentIDs.count > Self.incrementalVisibilityLimit
        {
            rebuildLedgerRelationshipVisibility()
        } else if affectedSegmentIDs.isEmpty == false || changes.sessionIDs.isEmpty == false {
            updateLedgerRelationshipVisibility(segmentIDs: affectedSegmentIDs)
            if changes.sessionIDs.isEmpty == false {
                publishIfChanged(\.sessions, readableLedgerSessions())
            }
        }
        publishIfChanged(\.activeSegments, ledgerDomainStore.activeSegments.filter(isReadableLedgerSegment))
        publishIfChanged(\.todaySegments, ledgerDomainStore.todaySegments.filter(isReadableLedgerSegment))
    }

    func isReadableLedgerSegment(_ segment: TimeSegment) -> Bool {
        readableLedgerSegmentIDs.contains(segment.id)
    }

    private func rebuildLedgerRelationshipVisibility() {
        let readableSnapshots = ledgerDomainStore.segmentSnapshotByID.values
            .filter(isReadableLedgerSnapshot)
            .sorted(by: Self.ledgerSnapshotOrder)
        readableLedgerSegmentIDs = Set(readableSnapshots.map(\.id))
        ledgerVisibilityExistingTaskIDs = existingTaskIDs
        // Assign only on change: each of these is observed, and an
        // unchanged reassignment would still invalidate every reader.
        publishIfChanged(\.allSegments, readableSnapshots.compactMap {
            ledgerDomainStore.segment(for: $0.id)
        })
        publishIfChanged(\.sessions, readableLedgerSessions())
    }

    /// Re-derives visibility for the changed segments only, keeping
    /// `allSegments` in ledger order without re-sorting the history.
    private func updateLedgerRelationshipVisibility(segmentIDs: Set<UUID>) {
        guard segmentIDs.isEmpty == false else { return }
        var segments = allSegments
        segments.removeAll { segmentIDs.contains($0.id) }
        readableLedgerSegmentIDs.subtract(segmentIDs)
        let readableSnapshots = segmentIDs
            .compactMap { ledgerDomainStore.segmentSnapshotByID[$0] }
            .filter(isReadableLedgerSnapshot)
        for snapshot in readableSnapshots {
            guard let segment = ledgerDomainStore.segment(for: snapshot.id) else { continue }
            let index = segments.partitioningIndex { existing in
                guard let existingSnapshot = ledgerDomainStore.segmentSnapshotByID[existing.id] else {
                    return false
                }
                return Self.ledgerSnapshotOrder(snapshot, existingSnapshot)
            }
            segments.insert(segment, at: index)
            readableLedgerSegmentIDs.insert(snapshot.id)
        }
        publishIfChanged(\.allSegments, segments)
    }

    private func isReadableLedgerSnapshot(_ snapshot: LedgerSegmentSnapshot) -> Bool {
        existingTaskIDs.contains(snapshot.taskID) &&
            ledgerDomainStore.session(for: snapshot.sessionID)?.taskID == snapshot.taskID
    }

    private func readableLedgerSessions() -> [TimeSession] {
        ledgerDomainStore.sessions.filter { existingTaskIDs.contains($0.taskID) }
    }

    private static func ledgerSnapshotOrder(
        _ lhs: LedgerSegmentSnapshot,
        _ rhs: LedgerSegmentSnapshot
    ) -> Bool {
        lhs.startedAt != rhs.startedAt ? lhs.startedAt < rhs.startedAt : lhs.id < rhs.id
    }

    private func publishIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<TimeTrackerStore, Value>,
        _ value: Value
    ) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}

private extension Array {
    /// First index whose element satisfies `belongsAfter`, for an array already
    /// partitioned so that every element satisfying it follows every one that
    /// does not.
    func partitioningIndex(where belongsAfter: (Element) -> Bool) -> Int {
        var lowerBound = startIndex
        var upperBound = endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if belongsAfter(self[middle]) {
                upperBound = middle
            } else {
                lowerBound = middle + 1
            }
        }
        return lowerBound
    }
}
