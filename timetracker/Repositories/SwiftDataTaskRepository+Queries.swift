import Foundation
import SwiftData

extension SwiftDataTaskRepository {
    func allNodes() throws -> [TaskNode] {
        let descriptor = FetchDescriptor<TaskNode>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.depth),
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return try context.fetch(descriptor)
    }

    func rootNodes() throws -> [TaskNode] {
        try children(of: nil)
    }

    func children(of parentID: UUID?) throws -> [TaskNode] {
        let parent = parentID
        let descriptor = FetchDescriptor<TaskNode>(
            predicate: #Predicate { $0.deletedAt == nil && $0.parentID == parent },
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return try context.fetch(descriptor)
    }

    func task(id: UUID) throws -> TaskNode? {
        let taskID = id
        var descriptor = FetchDescriptor<TaskNode>(
            predicate: #Predicate { $0.id == taskID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func tasks(ids: Set<UUID>) throws -> [TaskNode] {
        guard ids.isEmpty == false else { return [] }
        let requestedIDs = Array(ids)
        let descriptor = FetchDescriptor<TaskNode>(
            predicate: #Predicate { requestedIDs.contains($0.id) && $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.depth),
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return try context.fetch(descriptor)
    }
}
