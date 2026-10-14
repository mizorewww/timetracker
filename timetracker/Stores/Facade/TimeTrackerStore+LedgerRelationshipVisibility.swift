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
        let readableSessions = ledgerDomainStore.sessions.filter {
            existingTaskIDs.contains($0.taskID)
        }
        let taskIDBySessionID = Dictionary(
            readableSessions.map { ($0.id, $0.taskID) },
            uniquingKeysWith: { first, _ in first }
        )
        readableLedgerSegmentIDs = Set(ledgerDomainStore.allSegments.lazy.compactMap { segment in
            guard self.existingTaskIDs.contains(segment.taskID),
                  taskIDBySessionID[segment.sessionID] == segment.taskID
            else {
                return nil
            }
            return segment.id
        })

        // Assign only on change: each of these is observed, and an unchanged
        // reassignment would still invalidate every view that reads it.
        publishIfChanged(\.activeSegments, ledgerDomainStore.activeSegments.filter(isReadableLedgerSegment))
        publishIfChanged(\.todaySegments, ledgerDomainStore.todaySegments.filter(isReadableLedgerSegment))
        publishIfChanged(\.allSegments, ledgerDomainStore.allSegments.filter(isReadableLedgerSegment))
        publishIfChanged(\.sessions, readableSessions)
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
