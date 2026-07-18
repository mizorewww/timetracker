import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreTasksRouteTests {
    @Test @MainActor
    func editActionRoutesToTheSameTaskDestinationInEditingMode() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(
            title: "Editable",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        store.openTaskEditor(task.id)

        #expect(store.tasksRoute == .editor(taskID: task.id))
        #expect(store.tasksRoute?.taskID == task.id)
        #expect(store.tasksRoute?.startsEditing == true)
        #expect(store.selectedTaskID == task.id)
        #expect(store.desktopDestination == .tasks)
    }

    @Test @MainActor
    func openingAnUnavailableTaskLeavesTheCurrentRouteUntouched() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let current = try repository.createTask(
            title: "Current",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let deleted = try repository.createTask(
            title: "Deleted",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try repository.softDeleteTask(taskID: deleted.id)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.openTaskDetail(current.id)

        store.openTaskDetail(UUID())
        #expect(store.tasksRoute == .detail(taskID: current.id))
        #expect(store.selectedTaskID == current.id)

        store.openTaskDetail(deleted.id)
        #expect(store.tasksRoute == .detail(taskID: current.id))
        #expect(store.selectedTaskID == current.id)
    }

    @Test @MainActor
    func preparingTodayDetailSelectsTheTaskWithoutChangingItsNavigationSource() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(
            title: "Today detail",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.desktopDestination = .today

        let route = store.prepareTaskDetailRoute(task.id)

        #expect(route == .detail(taskID: task.id))
        #expect(store.selectedTaskID == task.id)
        #expect(store.tasksRoute == nil)
        #expect(store.desktopDestination == .today)
    }

    @Test @MainActor
    func deletingAParentClosesItsDescendantDetailRoute() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try repository.createTask(
            title: "Parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Child",
            parentID: parent.id,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.openTaskDetail(child.id)

        store.deleteSelectedTask(taskID: parent.id, preservingDestination: .tasks)

        #expect(store.tasksRoute == nil)
        #expect(store.task(for: parent.id) == nil)
        #expect(store.task(for: child.id) == nil)
        #expect(store.desktopDestination == .tasks)
    }

    @Test @MainActor
    func failedDeletionPreservesTheDetailRouteAndSelection() {
        let task = TaskNode(title: "Cannot delete", parentID: nil, deviceID: "test")
        let store = makeTestStore()
        store.tasks = [task]
        store.selectedTaskID = task.id
        store.tasksRoute = .detail(taskID: task.id)
        store.desktopDestination = .tasks

        store.deleteSelectedTask(taskID: task.id, preservingDestination: .tasks)

        #expect(store.errorMessage != nil)
        #expect(store.tasksRoute == .detail(taskID: task.id))
        #expect(store.selectedTaskID == task.id)
        #expect(store.desktopDestination == .tasks)
    }

    @Test @MainActor
    func refreshClearsADetailRouteWhoseTaskWasDeletedExternally() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(
            title: "Removed elsewhere",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.openTaskDetail(task.id)

        try repository.softDeleteTask(taskID: task.id)
        try store.refresh()

        #expect(store.tasksRoute == nil)
        #expect(store.task(for: task.id) == nil)
    }

    @Test @MainActor
    func externalDeletionInvalidatesAPreparedTodayRouteWithoutChangingItsSource() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(
            title: "Today route removed elsewhere",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.desktopDestination = .today
        let route = try #require(store.prepareTaskDetailRoute(task.id))

        try repository.softDeleteTask(taskID: task.id)
        try store.refresh()

        #expect(store.isTaskDetailRouteValid(route.taskID) == false)
        #expect(store.tasksRoute == nil)
        #expect(store.desktopDestination == .today)
    }
}
