import Foundation
import SwiftData
import Testing
@testable import timetracker

/// Guards historical persistence values without restoring a product workflow.
@Suite(.serialized)
struct CoreLegacyTaskStatusCompatibilityTests {
    @Test @MainActor
    func legacyPlannedActiveAndCompletedValuesRemainVisibleAndTrackable() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let planned = try repository.createTask(
            title: "Legacy planned",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let active = try repository.createTask(
            title: "Legacy active",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let completed = try repository.createTask(
            title: "Legacy completed",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let completedChild = try repository.createTask(
            title: "Ordinary child",
            parentID: completed.id,
            colorHex: nil,
            iconName: nil
        )
        planned.statusRaw = LegacyTaskStatusRaw.planned
        active.statusRaw = LegacyTaskStatusRaw.active
        completed.statusRaw = LegacyTaskStatusRaw.completed
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let expectedIDs = Set([planned.id, active.id, completed.id, completedChild.id])

        #expect(store.visibleTaskIDs.isSuperset(of: expectedIDs))
        #expect(store.trackableTaskIDs.isSuperset(of: expectedIDs))
        #expect(store.rootTasks().map(\.id).contains(completed.id))
        #expect(store.children(of: completed).map(\.id) == [completedChild.id])
        #expect(
            store.watchStateSnapshot().allTasksByUsage
                .map(\.taskID)
                .contains(completedChild.id)
        )
    }

    @Test @MainActor
    func legacyCompletedValueAllowsEveryTimerAdmissionPath() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let facadeTask = try repository.createTask(
            title: "Facade task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let systemTask = try repository.createTask(
            title: "System task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let watchTask = try repository.createTask(
            title: "Watch task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        for task in [facadeTask, systemTask, watchTask] {
            task.statusRaw = LegacyTaskStatusRaw.completed
        }
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.startTask(facadeTask)
        #expect(store.activeSegments.contains { $0.taskID == facadeTask.id })

        let systemSegmentID = try makeTestSystemActionCommandHandler().startTimer(
            taskID: systemTask.id,
            context: context
        )
        #expect(systemSegmentID != nil)

        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: watchTask.id,
            segmentID: nil,
            issuedAt: Date(),
            deviceID: "watch"
        )
        let watchResult = try makeTestWatchCommandProcessor(
            receiptStore: InMemoryWatchCommandReceiptStore()
        ).process(command, context: context)
        guard case .started = watchResult else {
            Issue.record("Expected the legacy completed task to start from Watch.")
            return
        }
        #expect(
            try SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
                .activeSegments()
                .contains { $0.taskID == watchTask.id }
        )
    }

    @Test @MainActor
    func completedChecklistDrivesProgressWithoutLockingTaskOrDescendants() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try repository.createTask(
            title: "Checklist parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Trackable child",
            parentID: parent.id,
            colorHex: nil,
            iconName: nil
        )
        context.insert(
            ChecklistItem(
                taskID: parent.id,
                title: "Finished quantity",
                isCompleted: true,
                deviceID: "test"
            )
        )
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(store.checklistProgress(for: parent.id).label == "1/1")
        #expect(store.rollup(for: parent.id)?.forecastState == .completed)
        #expect(store.isTaskAvailableForTracking(parent))
        #expect(store.isTaskAvailableForTracking(child))
        #expect(store.validParentTasks(for: child.id).map(\.id) == [parent.id])

        store.startTask(child)
        #expect(store.activeSegments.contains { $0.taskID == child.id })

        let presentationRouter = AppPresentationRouter()
        #expect(
            presentationRouter.presentNewTask(
                using: store,
                parentID: parent.id,
                preservingDestination: .tasks
            )
        )
    }

    @Test @MainActor
    func archiveStillRequiresEveryTimerInTheSubtreeToStop() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let parent = try taskRepository.createTask(
            title: "Parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try taskRepository.createTask(
            title: "Running child",
            parentID: parent.id,
            colorHex: nil,
            iconName: nil
        )
        let segment = try timeRepository.startTask(taskID: child.id, source: .timer)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(store.archiveSelectedTask(taskID: parent.id) == false)
        #expect(try taskRepository.task(id: parent.id)?.statusRaw == LegacyTaskStatusRaw.active)
        #expect(try taskRepository.task(id: parent.id)?.archivedAt == nil)
        #expect(store.errorMessage == AppStrings.localized("task.action.archive.stopFirst"))

        store.stop(segment: segment)
        #expect(try timeRepository.activeSegments().isEmpty)
        #expect(store.archiveSelectedTask(taskID: parent.id))

        let archived = try #require(try taskRepository.task(id: parent.id))
        #expect(archived.statusRaw == LegacyTaskStatusRaw.archived)
        #expect(archived.archivedAt != nil)
        #expect(archived.isArchivedForLifecycle)
    }

    @Test @MainActor
    func legacyCompletedTaskCanMoveAndAcceptChildren() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let legacyCompleted = try repository.createTask(
            title: "Imported project",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let destination = try repository.createTask(
            title: "Destination",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        legacyCompleted.statusRaw = LegacyTaskStatusRaw.completed
        try context.save()

        let newChild = try repository.createTask(
            title: "New child",
            parentID: legacyCompleted.id,
            colorHex: nil,
            iconName: nil
        )
        try repository.moveTask(
            taskID: legacyCompleted.id,
            newParentID: destination.id,
            sortOrder: 10
        )

        #expect(try repository.task(id: newChild.id)?.parentID == legacyCompleted.id)
        #expect(try repository.task(id: legacyCompleted.id)?.parentID == destination.id)
        #expect(
            try repository.task(id: legacyCompleted.id)?.statusRaw ==
                LegacyTaskStatusRaw.completed
        )
    }
}
