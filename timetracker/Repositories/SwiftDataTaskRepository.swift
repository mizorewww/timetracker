import Foundation
import SwiftData

@MainActor
final class SwiftDataTaskRepository: TaskRepository {
    private let context: ModelContext
    private let deviceID: String

    init(context: ModelContext, deviceID: String? = nil) {
        self.context = context
        self.deviceID = deviceID ?? DeviceIdentity.current
    }

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

    func categories() throws -> [TaskCategory] {
        let descriptor = FetchDescriptor<TaskCategory>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return try context.fetch(descriptor)
    }

    func categoryAssignments() throws -> [TaskCategoryAssignment] {
        let descriptor = FetchDescriptor<TaskCategoryAssignment>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.createdAt)
            ]
        )
        return try context.fetch(descriptor)
    }

    func category(id: UUID) throws -> TaskCategory? {
        let categoryID = id
        var descriptor = FetchDescriptor<TaskCategory>(
            predicate: #Predicate { $0.id == categoryID && $0.deletedAt == nil }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func categoryID(forRootTaskID taskID: UUID) throws -> UUID? {
        try activeCategoryAssignment(forRootTaskID: taskID)?.categoryID
    }

    @discardableResult
    func createCategory(
        title: String,
        colorHex: String? = nil,
        iconName: String? = nil,
        includesInForecast: Bool = true
    ) throws -> TaskCategory {
        let existing = try categories()
        let category = TaskCategory(
            title: title,
            deviceID: deviceID,
            colorHex: colorHex,
            iconName: iconName,
            includesInForecast: includesInForecast,
            sortOrder: (existing.last?.sortOrder ?? 0) + 10
        )
        context.insert(category)
        try context.save()
        return category
    }

    func updateCategory(
        categoryID: UUID,
        title: String,
        colorHex: String?,
        iconName: String?,
        includesInForecast: Bool
    ) throws {
        guard let category = try category(id: categoryID) else { return }
        category.title = title
        category.colorHex = colorHex
        category.iconName = iconName
        category.includesInForecast = includesInForecast
        category.updatedAt = Date()
        category.clientMutationID = UUID()
        try context.save()
    }

    func softDeleteCategory(categoryID: UUID) throws {
        guard let category = try category(id: categoryID) else { return }
        let now = Date()
        category.deletedAt = now
        category.updatedAt = now
        category.clientMutationID = UUID()

        for assignment in try categoryAssignments() where assignment.categoryID == categoryID {
            assignment.deletedAt = now
            assignment.updatedAt = now
            assignment.clientMutationID = UUID()
        }
        try context.save()
    }

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

    private func activeCategoryAssignment(forRootTaskID taskID: UUID) throws -> TaskCategoryAssignment? {
        let rootTaskID = taskID
        var descriptor = FetchDescriptor<TaskCategoryAssignment>(
            predicate: #Predicate { $0.taskID == rootTaskID && $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func setCategoryAssignment(categoryID: UUID?, forRootTaskID taskID: UUID) throws {
        let now = Date()
        let existing = try activeCategoryAssignment(forRootTaskID: taskID)

        guard let categoryID, try category(id: categoryID) != nil else {
            if let existing {
                existing.deletedAt = now
                existing.updatedAt = now
                existing.clientMutationID = UUID()
            }
            return
        }

        if let existing {
            existing.categoryID = categoryID
            existing.updatedAt = now
            existing.clientMutationID = UUID()
        } else {
            context.insert(TaskCategoryAssignment(taskID: taskID, categoryID: categoryID, deviceID: deviceID))
        }
    }

    private func canMove(nodeID: UUID, to newParentID: UUID?, nodes: [TaskNode]) -> Bool {
        guard let newParentID else { return true }
        guard nodeID != newParentID else { return false }
        return !descendantIDs(of: nodeID, nodes: nodes).contains(newParentID)
    }

    private func descendantIDs(of nodeID: UUID, nodes: [TaskNode], visited: Set<UUID> = []) -> Set<UUID> {
        guard !visited.contains(nodeID) else { return [] }
        let nextVisited = visited.union([nodeID])
        let directChildren = nodes.filter { $0.parentID == nodeID }
        return directChildren.reduce(into: Set<UUID>()) { result, child in
            result.insert(child.id)
            result.formUnion(descendantIDs(of: child.id, nodes: nodes, visited: nextVisited))
        }
    }

    private func applyHierarchy(to node: TaskNode, parentID: UUID?) throws {
        if let parentID, let parent = try task(id: parentID) {
            node.depth = parent.depth + 1
            node.path = parent.path + "/" + node.id.uuidString
        } else {
            node.depth = 0
            node.path = "/" + node.id.uuidString
        }
    }

    private func updateDescendantHierarchy(of node: TaskNode) throws {
        let children = try children(of: node.id)
        for child in children {
            child.depth = node.depth + 1
            child.path = node.path + "/" + child.id.uuidString
            child.updatedAt = Date()
            try updateDescendantHierarchy(of: child)
        }
    }
}
