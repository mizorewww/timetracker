import Foundation
import SwiftData

extension SwiftDataTimeTrackingRepository {
    func activeSegments() throws -> [TimeSegment] {
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.endedAt == nil }
        )
        let candidateIDs = Set(try context.fetch(descriptor).map(\.id))
        return try canonicalSegments(ids: candidateIDs)
            .filter { $0.endedAt == nil }
            .sorted(by: segmentStartOrder)
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
        try canonicalSegments(ids: ids).sorted(by: segmentStartOrder)
    }

    func segments(from: Date, to: Date) throws -> [TimeSegment] {
        try segments(from: from, to: to, now: nowProvider())
    }

    func segments(from: Date, to: Date, now: Date) throws -> [TimeSegment] {
        guard to > from else { return [] }
        let upperBound = to
        let lowerBound = from
        let activeSegmentEnd = min(now, upperBound)
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate {
                $0.startedAt < upperBound &&
                    ($0.endedAt ?? activeSegmentEnd) > lowerBound
            }
        )
        let candidateIDs = Set(try context.fetch(descriptor).map(\.id))
        return try canonicalSegments(ids: candidateIDs)
            .filter { segment in
                TrackedTimePolicy.overlaps(
                    startedAt: segment.startedAt,
                    endedAt: segment.endedAt,
                    interval: DateInterval(start: lowerBound, end: upperBound),
                    now: now
                )
            }
            .sorted(by: segmentStartOrder)
    }

    func allSegments() throws -> [TimeSegment] {
        try context.fetch(FetchDescriptor<TimeSegment>())
            .visibleDeduplicatedByID()
            .sorted(by: segmentStartOrder)
    }

    func canonicalSegments(ids: Set<UUID>) throws -> [TimeSegment] {
        guard ids.isEmpty == false else { return [] }
        let requestedIDs = Array(ids)
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { requestedIDs.contains($0.id) }
        )
        return try context.fetch(descriptor).visibleDeduplicatedByID()
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
        let tasks = try context.fetch(FetchDescriptor<TaskNode>()).deduplicatedByID()
        let trackableTaskIDs = TaskTrackingAvailabilityService().trackableTaskIDs(tasks: tasks)
        guard trackableTaskIDs.contains(taskID),
              let task = tasks.first(where: { $0.id == taskID }) else {
            throw TimeTrackingRepositoryError.taskUnavailable
        }
        return try LedgerPersistencePolicy.prepareTitleSnapshot(task.title)
    }

    private func segmentStartOrder(_ lhs: TimeSegment, _ rhs: TimeSegment) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func sessionStartOrder(_ lhs: TimeSession, _ rhs: TimeSession) -> Bool {
        if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
