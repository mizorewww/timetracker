import Foundation
import SwiftData

extension TimeTrackerStore {
    /// Re-reads which task rows exist, tombstones included. Task refreshes
    /// rebuild it; a ledger refresh re-reads it only when a row references a
    /// task ID it has not seen (for example a task inserted by another writer).
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
        let referencesUnknownTask = ledgerDomainStore.sessions.contains {
            existingTaskIDs.contains($0.taskID) == false
        }
        if referencesUnknownTask {
            try refreshExistingTaskIDs()
        }
        let ledgerRevision = ledgerDomainStore.relationshipRevision
        let historyChanged = ledgerRelationshipVisibilityKey.map {
            $0.ledgerRevision != ledgerRevision || $0.existingTaskIDs != existingTaskIDs
        } ?? true
        if historyChanged {
            let readableSessions = ledgerDomainStore.sessions.filter {
                existingTaskIDs.contains($0.taskID)
            }
            let taskIDBySessionID = Dictionary(
                readableSessions.map { ($0.id, $0.taskID) },
                uniquingKeysWith: { first, _ in first }
            )
            let readableSegments = ledgerDomainStore.allSegments.filter { segment in
                existingTaskIDs.contains(segment.taskID) &&
                    taskIDBySessionID[segment.sessionID] == segment.taskID
            }
            readableLedgerSegmentIDs = Set(readableSegments.map(\.id))
            ledgerRelationshipVisibilityKey = (ledgerRevision, existingTaskIDs)
            // Assign only on change: each of these is observed, and an
            // unchanged reassignment would still invalidate every reader.
            publishIfChanged(\.allSegments, readableSegments)
            publishIfChanged(\.sessions, readableSessions)
        }
        publishIfChanged(\.activeSegments, ledgerDomainStore.activeSegments.filter(isReadableLedgerSegment))
        publishIfChanged(\.todaySegments, ledgerDomainStore.todaySegments.filter(isReadableLedgerSegment))
    }

    func isReadableLedgerSegment(_ segment: TimeSegment) -> Bool {
        readableLedgerSegmentIDs.contains(segment.id)
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
