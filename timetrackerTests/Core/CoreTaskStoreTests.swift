import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreTaskStoreTests {
    @Test @MainActor
    func taskScopedRefreshRemovesMissingTaskSubtreeAndKeepsUnchangedRows() throws {
        let parent = TaskNode(title: "Deleted parent", parentID: nil, deviceID: "test", sortOrder: 10)
        let child = TaskNode(title: "Deleted child", parentID: parent.id, deviceID: "test", sortOrder: 10)
        let sibling = TaskNode(title: "Keep", parentID: nil, deviceID: "test", sortOrder: 20)

        let repository = TaskStoreTestRepository(tasks: [parent, child, sibling])
        var store = TaskStore()
        try store.refresh(repository: repository)

        repository.tasksByID = [sibling.id: sibling]
        try store.refreshTaskScoped(taskIDs: [parent.id], repository: repository)

        #expect(store.tasks.map(\.id) == [sibling.id])
    }

    @Test @MainActor
    func taskScopedRefreshReplacesFetchedTasksWithoutDroppingUnchangedRows() throws {
        let root = TaskNode(title: "Old", parentID: nil, deviceID: "test", sortOrder: 10)
        let sibling = TaskNode(title: "Keep", parentID: nil, deviceID: "test", sortOrder: 20)

        let repository = TaskStoreTestRepository(tasks: [root, sibling])
        var store = TaskStore()
        try store.refresh(repository: repository)

        let updated = TaskNode(title: "Updated", parentID: nil, deviceID: "test", sortOrder: 10)
        updated.id = root.id
        repository.tasksByID[root.id] = updated

        try store.refreshTaskScoped(taskIDs: [root.id], repository: repository)

        #expect(store.tasks.first { $0.id == root.id }?.title == "Updated")
        #expect(store.tasks.first { $0.id == sibling.id }?.title == "Keep")
    }
}

@MainActor
private final class TaskStoreTestRepository: TaskRepository {
    var tasksByID: [UUID: TaskNode]

    init(tasks: [TaskNode]) {
        tasksByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
    }

    func allNodes() throws -> [TaskNode] {
        tasksByID.values.sorted { $0.sortOrder < $1.sortOrder }
    }

    func rootNodes() throws -> [TaskNode] {
        try children(of: nil)
    }

    func children(of parentID: UUID?) throws -> [TaskNode] {
        try allNodes().filter { $0.parentID == parentID }
    }

    func task(id: UUID) throws -> TaskNode? {
        tasksByID[id]
    }

    func tasks(ids: Set<UUID>) throws -> [TaskNode] {
        ids.compactMap { tasksByID[$0] }
    }

    func categories() throws -> [TaskCategory] { [] }
    func categoryAssignments() throws -> [TaskCategoryAssignment] { [] }
    func category(id: UUID) throws -> TaskCategory? { nil }
    func categoryID(forRootTaskID taskID: UUID) throws -> UUID? { nil }

    func createCategory(title: String, colorHex: String?, iconName: String?, includesInForecast: Bool) throws -> TaskCategory {
        TaskCategory(title: title, deviceID: "test", colorHex: colorHex, iconName: iconName, includesInForecast: includesInForecast)
    }

    func updateCategory(categoryID: UUID, title: String, colorHex: String?, iconName: String?, includesInForecast: Bool) throws {}
    func softDeleteCategory(categoryID: UUID) throws {}

    func createTask(title: String, parentID: UUID?, categoryID: UUID?, colorHex: String?, iconName: String?) throws -> TaskNode {
        let task = TaskNode(title: title, parentID: parentID, deviceID: "test", colorHex: colorHex, iconName: iconName)
        tasksByID[task.id] = task
        return task
    }

    func updateTask(taskID: UUID, title: String, status: TaskStatus, parentID: UUID?, categoryID: UUID?, colorHex: String?, iconName: String?, notes: String?, estimatedSeconds: Int?, dueAt: Date?) throws {}
    func moveTask(taskID: UUID, newParentID: UUID?, sortOrder: Double) throws {}
    func setTaskStatus(taskID: UUID, status: TaskStatus) throws {}
    func archiveTask(taskID: UUID) throws {}
    func softDeleteTask(taskID: UUID) throws {
        tasksByID.removeValue(forKey: taskID)
    }
}
