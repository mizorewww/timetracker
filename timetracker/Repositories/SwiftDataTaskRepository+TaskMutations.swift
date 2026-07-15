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

        try applyHierarchy(to: node, parentID: parentID)
        context.insert(node)
        try setCategoryAssignment(categoryID: parentID == nil ? categoryID : nil, forRootTaskID: node.id)
        try context.saveAfterMutationStep()
        return node
    }

    func updateTask(
        taskID: UUID,
        title: String,
        status: TaskStatus,
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

        node.title = values.title
        node.status = status
        node.parentID = parentID
        node.colorHex = values.colorHex
        node.iconName = values.iconName
        node.notes = values.notes
        node.estimatedSeconds = TaskEstimatePolicy.normalized(seconds: estimatedSeconds)
        node.dueAt = dueAt
        let now = Date()
        node.updatedAt = now
        node.deviceID = deviceID
        node.clientMutationID = UUID()
        try applyHierarchy(
            to: node,
            parentID: parentID,
            requiresTrackableParent: isChangingParent
        )
        updateDescendantHierarchy(of: node, nodes: nodes, now: now)
        try setCategoryAssignment(categoryID: parentID == nil ? categoryID : nil, forRootTaskID: node.id)
        try context.saveAfterMutationStep()
    }

    func moveTask(taskID: UUID, newParentID: UUID?, sortOrder: Double) throws {
        let nodes = try allNodes()
        guard let node = nodes.first(where: { $0.id == taskID }) else { return }
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

    func setTaskStatus(taskID: UUID, status: TaskStatus) throws {
        guard let node = try task(id: taskID) else { return }
        node.status = status
        node.archivedAt = status == .archived ? Date() : nil
        node.updatedAt = Date()
        node.deviceID = deviceID
        node.clientMutationID = UUID()
        try context.saveAfterMutationStep()
    }

    func archiveTask(taskID: UUID) throws {
        guard let node = try task(id: taskID) else { return }
        node.status = .archived
        node.archivedAt = Date()
        node.updatedAt = Date()
        node.deviceID = deviceID
        node.clientMutationID = UUID()
        try context.saveAfterMutationStep()
    }

    func softDeleteTask(taskID: UUID) throws {
        let nodes = try allNodes()
        guard nodes.contains(where: { $0.id == taskID }) else { return }
        let now = Date()
        let idsToDelete = descendantIDs(of: taskID, nodes: nodes).union([taskID])
        for node in nodes where idsToDelete.contains(node.id) {
            node.deletedAt = now
            node.updatedAt = now
            node.deviceID = deviceID
            node.clientMutationID = UUID()
        }
        for assignment in try categoryAssignments() where idsToDelete.contains(assignment.taskID) {
            assignment.deletedAt = now
            assignment.updatedAt = now
            assignment.deviceID = deviceID
            assignment.clientMutationID = UUID()
        }
        try context.saveAfterMutationStep()
    }
}
