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

    func taskRecurrenceRules() throws -> [TaskRecurrenceRule] {
        try context.fetch(FetchDescriptor<TaskRecurrenceRule>())
            .visibleDeduplicatedByID()
            .sorted(by: persistentIdentityOrder)
    }

    func taskRecurrenceOccurrences() throws -> [TaskRecurrenceOccurrence] {
        try context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
            .visibleDeduplicatedByID()
            .sorted(by: persistentIdentityOrder)
    }

    func taskQuantityGoals() throws -> [TaskQuantityGoal] {
        try context.fetch(FetchDescriptor<TaskQuantityGoal>())
            .visibleDeduplicatedByID()
            .sorted(by: persistentIdentityOrder)
    }

    func taskQuantityEntries() throws -> [TaskQuantityEntry] {
        try context.fetch(FetchDescriptor<TaskQuantityEntry>())
            .visibleDeduplicatedByID()
            .sorted {
                if $0.recordedAt != $1.recordedAt {
                    return $0.recordedAt < $1.recordedAt
                }
                return persistentIdentityOrder($0, $1)
            }
    }

    func taskRecurrenceRules(
        taskIDs: Set<UUID>
    ) throws -> [TaskRecurrenceRule] {
        guard taskIDs.isEmpty == false else { return [] }
        let requestedIDs = Array(taskIDs)
        let descriptor = FetchDescriptor<TaskRecurrenceRule>(
            predicate: #Predicate {
                requestedIDs.contains($0.templateTaskID)
            }
        )
        return try context.fetch(descriptor)
            .visibleDeduplicatedByID()
            .sorted(by: persistentIdentityOrder)
    }

    func taskRecurrenceOccurrences(
        taskIDs: Set<UUID>
    ) throws -> [TaskRecurrenceOccurrence] {
        guard taskIDs.isEmpty == false else { return [] }
        let requestedIDs = Array(taskIDs)
        let descriptor = FetchDescriptor<TaskRecurrenceOccurrence>(
            predicate: #Predicate {
                requestedIDs.contains($0.templateTaskID) ||
                    requestedIDs.contains($0.generatedTaskID)
            }
        )
        return try context.fetch(descriptor)
            .visibleDeduplicatedByID()
            .sorted(by: persistentIdentityOrder)
    }

    func taskQuantityGoals(
        taskIDs: Set<UUID>
    ) throws -> [TaskQuantityGoal] {
        guard taskIDs.isEmpty == false else { return [] }
        let requestedIDs = Array(taskIDs)
        let descriptor = FetchDescriptor<TaskQuantityGoal>(
            predicate: #Predicate { requestedIDs.contains($0.taskID) }
        )
        return try context.fetch(descriptor)
            .visibleDeduplicatedByID()
            .sorted(by: persistentIdentityOrder)
    }

    func taskQuantityEntries(
        taskIDs: Set<UUID>
    ) throws -> [TaskQuantityEntry] {
        guard taskIDs.isEmpty == false else { return [] }
        let requestedIDs = Array(taskIDs)
        let descriptor = FetchDescriptor<TaskQuantityEntry>(
            predicate: #Predicate { requestedIDs.contains($0.taskID) }
        )
        return try context.fetch(descriptor)
            .visibleDeduplicatedByID()
            .sorted {
                if $0.recordedAt != $1.recordedAt {
                    return $0.recordedAt < $1.recordedAt
                }
                return persistentIdentityOrder($0, $1)
            }
    }

    private func taskHierarchyOrder(_ lhs: TaskNode, _ rhs: TaskNode) -> Bool {
        if lhs.depth != rhs.depth {
            return lhs.depth < rhs.depth
        }
        return taskSiblingOrder(lhs, rhs)
    }

    private func taskSiblingOrder(_ lhs: TaskNode, _ rhs: TaskNode) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func persistentIdentityOrder<Model: PersistentUUIDModel>(
        _ lhs: Model,
        _ rhs: Model
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}
