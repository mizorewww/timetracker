import Foundation
import SwiftData

extension TimeTrackerStore {
    /// Keeps temporarily incomplete CloudKit relationship graphs in SwiftData
    /// without publishing them to totals or system surfaces. A later full
    /// refresh makes the rows visible as soon as their parent records arrive.
    func refreshLedgerRelationshipVisibility() throws {
        guard let modelContext else {
            readableLedgerSegmentIDs = []
            activeSegments = []
            todaySegments = []
            allSegments = []
            sessions = []
            return
        }

        let existingTaskIDs = Set(
            try modelContext.fetch(FetchDescriptor<TaskNode>())
                .deduplicatedByID()
                .map(\.id)
        )
        let readableSessions = ledgerDomainStore.sessions.filter {
            existingTaskIDs.contains($0.taskID)
        }
        let taskIDBySessionID = Dictionary(
            uniqueKeysWithValues: readableSessions.map { ($0.id, $0.taskID) }
        )

        readableLedgerSegmentIDs = Set(ledgerDomainStore.allSegments.compactMap { segment in
            guard existingTaskIDs.contains(segment.taskID),
                  taskIDBySessionID[segment.sessionID] == segment.taskID else {
                return nil
            }
            return segment.id
        })

        activeSegments = ledgerDomainStore.activeSegments.filter(isReadableLedgerSegment)
        todaySegments = ledgerDomainStore.todaySegments.filter(isReadableLedgerSegment)
        allSegments = ledgerDomainStore.allSegments.filter(isReadableLedgerSegment)
        sessions = readableSessions
    }

    func isReadableLedgerSegment(_ segment: TimeSegment) -> Bool {
        readableLedgerSegmentIDs.contains(segment.id)
    }
}
