import Foundation
import SwiftData

extension SwiftDataTaskRepository {
    func allNodes() throws -> [TaskNode] {
        try context.fetch(FetchDescriptor<TaskNode>())
            .visibleDeduplicatedByID()
            .sorted(by: taskHierarchyOrder)
    }

    func rootNodes() throws -> [TaskNode] {
        try children(of: nil)
    }

    func children(of parentID: UUID?) throws -> [TaskNode] {
        let parent = parentID
        return try allNodes()
            .filter { $0.parentID == parent }
            .sorted(by: taskSiblingOrder)
    }

    func task(id: UUID) throws -> TaskNode? {
        let taskID = id
        let descriptor = FetchDescriptor<TaskNode>(predicate: #Predicate { $0.id == taskID })
        return try context.fetch(descriptor).visibleDeduplicatedByID().first
    }

    func tasks(ids: Set<UUID>) throws -> [TaskNode] {
        guard ids.isEmpty == false else { return [] }
        let requestedIDs = Array(ids)
        let descriptor = FetchDescriptor<TaskNode>(
            predicate: #Predicate { requestedIDs.contains($0.id) }
        )
        return try context.fetch(descriptor)
            .visibleDeduplicatedByID()
            .sorted(by: taskHierarchyOrder)
    }

    private func taskHierarchyOrder(_ lhs: TaskNode, _ rhs: TaskNode) -> Bool {
        if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
        return taskSiblingOrder(lhs, rhs)
    }

    private func taskSiblingOrder(_ lhs: TaskNode, _ rhs: TaskNode) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
