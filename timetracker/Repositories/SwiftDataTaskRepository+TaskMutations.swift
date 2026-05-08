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
        let siblings = try children(of: parentID)
        let node = TaskNode(
            title: title,
            parentID: parentID,
            deviceID: deviceID,
            colorHex: colorHex,
            iconName: iconName,
            sortOrder: (siblings.last?.sortOrder ?? 0) + 10
        )

        try applyHierarchy(to: node, parentID: parentID)
        context.insert(node)
        try setCategoryAssignment(categoryID: parentID == nil ? categoryID : nil, forRootTaskID: node.id)
        try context.save()
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
        let nodes = try allNodes()
        guard let node = nodes.first(where: { $0.id == taskID }) else { return }
        guard canMove(nodeID: taskID, to: parentID, nodes: nodes) else {
            throw TaskRepositoryError.invalidMove
        }

        node.title = title
        node.status = status
        node.parentID = parentID
        node.colorHex = colorHex
        node.iconName = iconName
        node.notes = notes
        node.estimatedSeconds = estimatedSeconds
        node.dueAt = dueAt
        node.updatedAt = Date()
        node.clientMutationID = UUID()
        try applyHierarchy(to: node, parentID: parentID)
        try updateDescendantHierarchy(of: node)
        try setCategoryAssignment(categoryID: parentID == nil ? categoryID : nil, forRootTaskID: node.id)
        try context.save()
    }

    func moveTask(taskID: UUID, newParentID: UUID?, sortOrder: Double) throws {
        let nodes = try allNodes()
        guard let node = nodes.first(where: { $0.id == taskID }) else { return }
        guard canMove(nodeID: taskID, to: newParentID, nodes: nodes) else {
            throw TaskRepositoryError.invalidMove
        }

        node.parentID = newParentID
        node.sortOrder = sortOrder
        node.updatedAt = Date()
        node.clientMutationID = UUID()
        try applyHierarchy(to: node, parentID: newParentID)
        try updateDescendantHierarchy(of: node)
        if newParentID != nil {
            try setCategoryAssignment(categoryID: nil, forRootTaskID: node.id)
        }
        try context.save()
    }

    func setTaskStatus(taskID: UUID, status: TaskStatus) throws {
        guard let node = try task(id: taskID) else { return }
        node.status = status
        node.archivedAt = status == .archived ? Date() : nil
        node.updatedAt = Date()
        node.clientMutationID = UUID()
        try context.save()
    }

    func archiveTask(taskID: UUID) throws {
        guard let node = try task(id: taskID) else { return }
        node.status = .archived
        node.archivedAt = Date()
        node.updatedAt = Date()
        node.clientMutationID = UUID()
        try context.save()
    }

    func softDeleteTask(taskID: UUID) throws {
        let nodes = try allNodes()
        guard nodes.contains(where: { $0.id == taskID }) else { return }
        let now = Date()
        let idsToDelete = descendantIDs(of: taskID, nodes: nodes).union([taskID])
        for node in nodes where idsToDelete.contains(node.id) {
            node.deletedAt = now
            node.updatedAt = now
            node.clientMutationID = UUID()
        }
        for assignment in try categoryAssignments() where idsToDelete.contains(assignment.taskID) {
            assignment.deletedAt = now
            assignment.updatedAt = now
            assignment.clientMutationID = UUID()
        }
        try context.save()
    }
}
