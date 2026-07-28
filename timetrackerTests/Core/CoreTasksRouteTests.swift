import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreTasksRouteTests {
    @Test @MainActor
    func openingATaskUsesTheSingleDetailWorkspaceRoute() throws {
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

        store.openTaskDetail(task.id)

        #expect(store.tasksRoute == .detail(taskID: task.id))
        #expect(store.tasksRoute?.taskID == task.id)
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
        let tombstonedAt = deleted.updatedAt.addingTimeInterval(1)
        deleted.deletedAt = tombstonedAt
        deleted.updatedAt = tombstonedAt
        deleted.deviceID = "legacy-sync"
        deleted.clientMutationID = UUID()
        try context.save()
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
    func openingTodayDetailKeepsItsRouteAboveAdaptiveShells() throws {
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

        store.openTodayTaskDetail(task.id)

        #expect(store.todayTaskRoute == .detail(taskID: task.id))
        #expect(store.selectedTaskID == task.id)
        #expect(store.tasksRoute == nil)
        #expect(store.desktopDestination == .today)
    }

    @Test @MainActor
    func failedProtectedArchiveKeepsTheDirtyDraft() throws {
        let store = makeTestStore()
        let taskID = UUID()
        let registrationID = UUID()
        var isDirty = true
        var discardCount = 0
        store.taskDetailNavigationGuard.register(
            id: registrationID,
            taskID: taskID,
            hasUnsavedChanges: { isDirty },
            discardChanges: {
                isDirty = false
                discardCount += 1
                return true
            },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )

        store.archiveTaskProtectingUnsavedChanges(taskID)
        let requestID = try #require(
            store.taskDetailNavigationGuard.pendingNavigationID
        )
        let didComplete = store.taskDetailNavigationGuard
            .discardChangesAndCompletePendingNavigation(
                requestID: requestID
            )

        #expect(didComplete == false)
        #expect(isDirty)
        #expect(discardCount == 0)
        #expect(store.taskDetailNavigationGuard.hasPendingNavigation == false)
        #expect(store.errorMessage != nil)
    }

    @Test @MainActor
    func successfulProtectedArchiveDiscardsAndClosesTheDetailRoute() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Archive after confirmation",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.openTaskDetail(task.id)
        let registrationID = UUID()
        var isDirty = true
        var dismissCount = 0
        store.taskDetailNavigationGuard.register(
            id: registrationID,
            taskID: task.id,
            hasUnsavedChanges: { isDirty },
            discardChanges: {
                isDirty = false
                return true
            },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {
                dismissCount += 1
                store.closeTaskDetailNavigation()
            }
        )

        store.archiveTaskProtectingUnsavedChanges(task.id)
        let requestID = try #require(
            store.taskDetailNavigationGuard.pendingNavigationID
        )
        #expect(
            store.taskDetailNavigationGuard
                .discardChangesAndCompletePendingNavigation(
                    requestID: requestID
                )
        )

        #expect(isDirty == false)
        #expect(dismissCount == 1)
        #expect(store.tasksRoute == nil)
        #expect(store.isTaskDetailRouteValid(task.id) == false)
    }

    @Test @MainActor
    func archivingAParentClosesItsDescendantDetailRouteAndRestoreReturnsTheBranch() throws {
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

        #expect(store.archiveSelectedTask(taskID: parent.id))

        #expect(store.tasksRoute == nil)
        #expect(store.isTaskDetailRouteValid(child.id) == false)
        #expect(store.isTaskVisible(parent) == false)
        #expect(store.isTaskVisible(child) == false)
        #expect(store.desktopDestination == .tasks)

        #expect(store.unarchiveTask(taskID: parent.id))
        #expect(store.isTaskDetailRouteValid(child.id))
        #expect(store.isTaskVisible(parent))
        #expect(store.isTaskVisible(child))
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

        let siblingContext = ModelContext(context.container)
        let siblingTask = try #require(
            try SwiftDataTaskRepository(
                context: siblingContext,
                deviceID: "external-sync"
            ).task(id: task.id)
        )
        let tombstonedAt = siblingTask.updatedAt.addingTimeInterval(1)
        siblingTask.deletedAt = tombstonedAt
        siblingTask.updatedAt = tombstonedAt
        siblingTask.deviceID = "external-sync"
        siblingTask.clientMutationID = UUID()
        try siblingContext.save()
        try store.refresh()

        #expect(store.tasksRoute == nil)
        #expect(store.task(for: task.id) == nil)
    }

    @Test @MainActor
    func refreshPreservesADirtyDetailDraftWhenItsTaskIsDeletedExternally() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let task = try repository.createTask(
            title: "Preserve my draft",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.openTaskDetail(task.id)
        let registrationID = UUID()
        var isDirty = true
        store.taskDetailNavigationGuard.register(
            id: registrationID,
            taskID: task.id,
            hasUnsavedChanges: { isDirty },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )

        let siblingContext = ModelContext(context.container)
        let siblingTask = try #require(
            try SwiftDataTaskRepository(
                context: siblingContext,
                deviceID: "external-sync"
            ).task(id: task.id)
        )
        let tombstonedAt = siblingTask.updatedAt.addingTimeInterval(1)
        siblingTask.deletedAt = tombstonedAt
        siblingTask.updatedAt = tombstonedAt
        siblingTask.deviceID = "external-sync"
        siblingTask.clientMutationID = UUID()
        try siblingContext.save()
        try store.refresh()

        #expect(store.tasksRoute == .detail(taskID: task.id))
        #expect(store.task(for: task.id) == nil)
        #expect(store.shouldRetainTaskDetailRoute(task.id))

        isDirty = false
        #expect(store.shouldRetainTaskDetailRoute(task.id) == false)
        store.validateSelectedTask()

        #expect(store.tasksRoute == nil)
    }

    @Test @MainActor
    func refreshPreservesDirtyDraftWhenItsTaskIsArchivedExternally() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Archived elsewhere",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.openTaskDetail(task.id)
        var isDirty = true
        store.taskDetailNavigationGuard.register(
            id: UUID(),
            taskID: task.id,
            hasUnsavedChanges: { isDirty },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )

        try SwiftDataTaskRepository(
            context: ModelContext(context.container),
            deviceID: "external-sync"
        ).archiveTask(taskID: task.id)
        try store.refresh()

        #expect(store.tasksRoute == .detail(taskID: task.id))
        #expect(store.isTaskDetailRouteValid(task.id) == false)
        #expect(store.shouldRetainTaskDetailRoute(task.id))

        isDirty = false
        store.validateSelectedTask()

        #expect(store.tasksRoute == nil)
    }

    @Test @MainActor
    func refreshPreservesDirtyChildDraftWhenItsParentIsArchivedExternally() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let parent = try repository.createTask(
            title: "Parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Child draft",
            parentID: parent.id,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.openTaskDetail(child.id)
        var isDirty = true
        store.taskDetailNavigationGuard.register(
            id: UUID(),
            taskID: child.id,
            hasUnsavedChanges: { isDirty },
            requestDiscardConfirmation: { _ in },
            dismissDetail: {}
        )

        try SwiftDataTaskRepository(
            context: ModelContext(context.container),
            deviceID: "external-sync"
        ).archiveTask(taskID: parent.id)
        try store.refresh()

        #expect(store.tasksRoute == .detail(taskID: child.id))
        #expect(store.isTaskDetailRouteValid(child.id) == false)
        #expect(store.shouldRetainTaskDetailRoute(child.id))

        isDirty = false
        store.validateSelectedTask()

        #expect(store.tasksRoute == nil)
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

        let tombstonedAt = task.updatedAt.addingTimeInterval(1)
        task.deletedAt = tombstonedAt
        task.updatedAt = tombstonedAt
        task.deviceID = "external-sync"
        task.clientMutationID = UUID()
        try context.save()
        try store.refresh()

        #expect(store.isTaskDetailRouteValid(route.taskID) == false)
        #expect(store.tasksRoute == nil)
        #expect(store.desktopDestination == .today)
    }
}
