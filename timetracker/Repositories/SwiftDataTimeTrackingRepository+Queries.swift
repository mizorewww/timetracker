import Foundation
import SwiftData

extension SwiftDataTimeTrackingRepository {
    func activeSegments() throws -> [TimeSegment] {
        try canonicalSegments(
            nominating: FetchDescriptor<TimeSegment>(
                predicate: #Predicate { $0.endedAt == nil }
            ),
            matching: { $0.endedAt == nil }
        )
    }

    func sessions() throws -> [TimeSession] {
        try context.fetch(FetchDescriptor<TimeSession>())
            .visibleDeduplicatedByID()
            .sorted(by: sessionStartOrder)
    }

    func sessions(ids: Set<UUID>) throws -> [TimeSession] {
        guard ids.isEmpty == false else { return [] }
        let sessionIDs = Array(ids)
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { sessionIDs.contains($0.id) }
        )
        return try context.fetch(descriptor)
            .visibleDeduplicatedByID()
            .sorted(by: sessionStartOrder)
    }

    func segments(ids: Set<UUID>) throws -> [TimeSegment] {
        try canonicalSegments(ids: ids).sorted(by: TimeSegment.startOrder)
    }

    func segments(sessionIDs: Set<UUID>) throws -> [TimeSegment] {
        guard sessionIDs.isEmpty == false else { return [] }
        let requestedSessionIDs = Array(sessionIDs)
        return try canonicalSegments(
            nominating: FetchDescriptor<TimeSegment>(
                predicate: #Predicate { requestedSessionIDs.contains($0.sessionID) }
            ),
            matching: { sessionIDs.contains($0.sessionID) }
        )
    }

    func segments(from: Date, to: Date) throws -> [TimeSegment] {
        try segments(from: from, to: to, now: nowProvider())
    }

    func segments(from: Date, to: Date, now: Date) throws -> [TimeSegment] {
        guard to > from else { return [] }
        let upperBound = to
        let lowerBound = from
        let activeSegmentEnd = min(now, upperBound)
        return try canonicalSegments(
            nominating: FetchDescriptor<TimeSegment>(
                predicate: #Predicate {
                    $0.startedAt < upperBound &&
                        ($0.endedAt ?? activeSegmentEnd) > lowerBound
                }
            ),
            matching: { segment in
                TrackedTimePolicy.overlaps(
                    startedAt: segment.startedAt,
                    endedAt: segment.endedAt,
                    interval: DateInterval(start: lowerBound, end: upperBound),
                    now: now
                )
            }
        )
    }

    func allSegments() throws -> [TimeSegment] {
        try context.fetch(FetchDescriptor<TimeSegment>())
            .visibleDeduplicatedByID()
            .sorted(by: TimeSegment.startOrder)
    }

    func canonicalSegments(ids: Set<UUID>) throws -> [TimeSegment] {
        guard ids.isEmpty == false else { return [] }
        let requestedIDs = Array(ids)
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { requestedIDs.contains($0.id) }
        )
        return try context.fetch(descriptor).visibleDeduplicatedByID()
    }

    private func canonicalSegments(
        nominating descriptor: FetchDescriptor<TimeSegment>,
        matching postFilter: (TimeSegment) -> Bool
    ) throws -> [TimeSegment] {
        let candidateIDs = try Set(context.fetch(descriptor).map(\.id))
        return try canonicalSegments(ids: candidateIDs)
            .filter(postFilter)
            .sorted(by: TimeSegment.startOrder)
    }

    func canonicalSessions(ids: Set<UUID>) throws -> [TimeSession] {
        guard ids.isEmpty == false else { return [] }
        let requestedIDs = Array(ids)
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { requestedIDs.contains($0.id) }
        )
        return try context.fetch(descriptor).visibleDeduplicatedByID()
    }

    func preparedTrackableTitleSnapshot(for taskID: UUID) throws -> String? {
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: deviceID
        )
        guard let task = try taskRepository.directWorkTask(id: taskID) else {
            throw TimeTrackingRepositoryError.taskUnavailable
        }
        return try LedgerPersistencePolicy.prepareTitleSnapshot(task.title)
    }

    private func sessionStartOrder(_ lhs: TimeSession, _ rhs: TimeSession) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt > rhs.startedAt
        }
        return lhs.id < rhs.id
    }
}
