import Foundation
import SwiftData

nonisolated extension SwiftDataTaskRepository {
    @discardableResult
    func createTask(
        proposedID: UUID = UUID(),
        title: String,
        parentID: UUID?,
        categoryID: UUID? = nil,
        colorHex: String? = nil,
        iconName: String? = nil
    ) throws -> TaskNode {
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
            sortOrder: SortOrderPolicy.after(siblings.last?.sortOrder)
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
        node.markMutated(at: now, deviceID: deviceID)
        if isChangingParent {
            try applyHierarchy(to: node, parentID: parentID)
        }
        updateDescendantHierarchy(of: node, nodes: nodes, now: now)
        try setCategoryAssignment(categoryID: parentID == nil ? categoryID : nil, forRootTaskID: node.id)
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
        node.markMutated(at: mutationDate, deviceID: deviceID)
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
        node.markMutated(at: mutationDate, deviceID: deviceID)
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
