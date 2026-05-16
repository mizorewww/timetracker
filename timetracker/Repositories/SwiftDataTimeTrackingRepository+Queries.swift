import Foundation
import SwiftData

extension SwiftDataTimeTrackingRepository {
    func activeSegments() throws -> [TimeSegment] {
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.deletedAt == nil && $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor)
    }

    func sessions() throws -> [TimeSession] {
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func sessions(ids: Set<UUID>) throws -> [TimeSession] {
        guard ids.isEmpty == false else { return [] }
        let sessionIDs = Array(ids)
        let descriptor = FetchDescriptor<TimeSession>(
            predicate: #Predicate { sessionIDs.contains($0.id) && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func segments(from: Date, to: Date) throws -> [TimeSegment] {
        try segments(from: from, to: to, now: Date())
    }

    func segments(from: Date, to: Date, now: Date) throws -> [TimeSegment] {
        let upperBound = to
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.deletedAt == nil && $0.startedAt < upperBound },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor).filter { segment in
            let end = min(segment.endedAt ?? now, upperBound)
            return end > from
        }
    }

    func allSegments() throws -> [TimeSegment] {
        let descriptor = FetchDescriptor<TimeSegment>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        return try context.fetch(descriptor)
    }
}
