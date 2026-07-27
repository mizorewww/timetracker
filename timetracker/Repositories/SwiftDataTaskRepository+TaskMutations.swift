import Foundation
import SwiftData

extension SwiftDataTaskRepository {
    @discardableResult
    func createTask(
        title: String,
        parentID: UUID?,
        categoryID: UUID? = nil,
        colorHex: String? = nil,
        iconName: String? = nil
    ) throws -> TaskNode {
        try createTask(
            proposedID: UUID(),
            title: title,
            parentID: parentID,
            categoryID: categoryID,
            colorHex: colorHex,
            iconName: iconName
        )
    }

    /// Creates a task with an identity chosen by an enclosing idempotent
    /// command. This remains a concrete-repository API so ordinary callers
    /// continue to receive repository-owned UUIDs through `TaskRepository`.
    @discardableResult
    func createTask(
        proposedID: UUID,
        title: String,
        parentID: UUID?,
        categoryID: UUID? = nil,
        colorHex: String? = nil,
        iconName: String? = nil
    ) throws -> TaskNode {
        try validateAppleHealthPlacement(taskID: proposedID, parentID: parentID, categoryID: categoryID)
        let values = try TaskPersistencePolicy.prepareTask(
            title: title,
            colorHex: colorHex,
            iconName: iconName,
            notes: nil
        )
        let siblings = try children(of: parentID)
        let node = TaskNode(
            title: values.title,
            parentID: parentID,
            deviceID: deviceID,
            colorHex: values.colorHex,
            iconName: values.iconName,
            sortOrder: (siblings.last?.sortOrder ?? 0) + 10
        )
        node.id = proposedID

        try applyHierarchy(to: node, parentID: parentID)
        context.insert(node)
        try setCategoryAssignment(categoryID: parentID == nil ? categoryID : nil, forRootTaskID: node.id)
        try context.saveAfterMutationStep()
        return node
    }

    func updateTask(
        taskID: UUID,
        title: String,
        parentID: UUID?,
        categoryID: UUID?,
        colorHex: String?,
        iconName: String?,
        notes: String?,
        estimatedSeconds: Int?,
        dueAt: Date?
    ) throws {
        let values = try TaskPersistencePolicy.prepareTask(
            title: title,
            colorHex: colorHex,
            iconName: iconName,
            notes: notes
        )
        let nodes = try allNodes()
        guard let node = nodes.first(where: { $0.id == taskID }) else { return }
        try validateAppleHealthPlacement(taskID: taskID, parentID: parentID, categoryID: categoryID)
        let isChangingParent = node.parentID != parentID
        guard canMove(nodeID: taskID, to: parentID, nodes: nodes) else {
            throw TaskRepositoryError.invalidMove
        }

        let now = Date()
        node.title = values.title
        node.parentID = parentID
        node.colorHex = values.colorHex
        node.iconName = values.iconName
        node.notes = values.notes
        node.estimatedSeconds = TaskEstimatePolicy.normalized(seconds: estimatedSeconds)
        node.dueAt = dueAt
        node.updatedAt = now
        node.deviceID = deviceID
        node.clientMutationID = UUID()
        if isChangingParent {
            try applyHierarchy(to: node, parentID: parentID)
        }
        updateDescendantHierarchy(of: node, nodes: nodes, now: now)
        try setCategoryAssignment(categoryID: parentID == nil ? categoryID : nil, forRootTaskID: node.id)
        try context.saveAfterMutationStep()
    }

    func moveTask(taskID: UUID, newParentID: UUID?, sortOrder: Double) throws {
        let nodes = try allNodes()
        guard let node = nodes.first(where: { $0.id == taskID }) else { return }
        try validateAppleHealthParentPlacement(taskID: taskID, parentID: newParentID)
        guard canMove(nodeID: taskID, to: newParentID, nodes: nodes) else {
            throw TaskRepositoryError.invalidMove
        }

        node.parentID = newParentID
        node.sortOrder = sortOrder
        let now = Date()
        node.updatedAt = now
        node.deviceID = deviceID
        node.clientMutationID = UUID()
        try applyHierarchy(to: node, parentID: newParentID)
        updateDescendantHierarchy(of: node, nodes: nodes, now: now)
        if newParentID != nil {
            try setCategoryAssignment(categoryID: nil, forRootTaskID: node.id)
        }
        try context.saveAfterMutationStep()
    }

    func archiveTask(taskID: UUID) throws {
        guard let target = try lifecycleMutationTarget(taskID: taskID) else {
            return
        }
        let now = Date()
        let mutationDate = PersistentLWWMutationDate.strictlyDominating(
            preferred: now,
            observed: target.observedUpdatedDates
        )
        let node = target.node
        node.statusRaw = LegacyTaskStatusRaw.archived
        node.archivedAt = node.archivedAt ?? mutationDate
        node.updatedAt = mutationDate
        node.deviceID = deviceID
        node.clientMutationID = UUID()
        try context.saveAfterMutationStep()
    }

    func unarchiveTask(taskID: UUID) throws {
        guard let target = try lifecycleMutationTarget(taskID: taskID),
              target.node.isArchivedForLifecycle
        else {
            return
        }
        let now = Date()
        let mutationDate = PersistentLWWMutationDate.strictlyDominating(
            preferred: now,
            observed: target.observedUpdatedDates
        )
        let node = target.node
        node.archivedAt = nil
        if node.statusRaw == LegacyTaskStatusRaw.archived {
            node.statusRaw = LegacyTaskStatusRaw.active
        }
        node.updatedAt = mutationDate
        node.deviceID = deviceID
        node.clientMutationID = UUID()
        try context.saveAfterMutationStep()
    }

    private func lifecycleMutationTarget(
        taskID: UUID
    ) throws -> (node: TaskNode, observedUpdatedDates: [Date])? {
        let requestedTaskID = taskID
        let descriptor = FetchDescriptor<TaskNode>(
            predicate: #Predicate { $0.id == requestedTaskID }
        )
        let candidates = try context.fetch(descriptor)
        guard let node = candidates.deduplicatedByID().first,
              node.deletedAt == nil
        else {
            return nil
        }
        return (node, candidates.map(\.updatedAt))
    }
}
