import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedTaskLifecycleCommandCoordinatorTests {
    @Test
    func staleSceneCannotCompleteSubtreeStartedBySiblingContext() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try taskRepository.createTask(
            title: "Parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try taskRepository.createTask(
            title: "Child",
            parentID: parent.id,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.activeSegments.isEmpty)

        _ = try makeTestSystemActionCommandHandler().startTimerMutation(
            taskID: child.id,
            container: context.container
        )

        #expect(store.setTaskStatus(.completed, taskID: parent.id) == false)
        #expect(
            try freshTaskRepository(context.container).task(id: parent.id)?.status == .active
        )
        #expect(store.errorMessage == AppStrings.localized("task.action.complete.stopFirst"))
    }

    @Test
    func staleSceneCanCompleteAfterSiblingContextStopsTimer() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Fresh stop",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let segment = try SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
            .startTask(taskID: task.id, source: .timer)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.activeSegments.map(\.id) == [segment.id])

        _ = try makeTestSystemActionCommandHandler().stopTimerMutation(
            segmentID: segment.id,
            container: context.container
        )

        #expect(store.setTaskStatus(.completed, taskID: task.id))
        #expect(
            try freshTaskRepository(context.container).task(id: task.id)?.status == .completed
        )
        #expect(store.activeSegments.isEmpty)
    }

    @Test
    func breakOnlyPomodoroStillBlocksArchive() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Resting task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        #expect(
            store.startPomodoro(
                taskID: task.id,
                focusSeconds: 60,
                breakSeconds: 60,
                targetRounds: 2
            )
        )
        let focusRun = try #require(store.activePomodoroRun)
        #expect(
            store.completeActivePomodoroFocus(
                phase: PomodoroPhaseToken(run: focusRun)
            )
        )
        #expect(store.activeSegments.isEmpty)
        #expect(store.activePomodoroRun?.state == .shortBreak)

        #expect(store.archiveSelectedTask(taskID: task.id) == false)
        #expect(
            try freshTaskRepository(context.container).task(id: task.id)?.status == .active
        )
        #expect(store.errorMessage == AppStrings.localized("task.action.archive.stopFirst"))
    }

    @Test
    func staleSceneDeletionDiscoversSiblingChildAndStopsItsTimer() throws {
        let context = try makeTestContext()
        let parent = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Known parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.task(for: parent.id) != nil)

        let siblingContext = ModelContext(context.container)
        let child = try SwiftDataTaskRepository(
            context: siblingContext,
            deviceID: "sibling"
        ).createTask(
            title: "Late child",
            parentID: parent.id,
            colorHex: nil,
            iconName: nil
        )
        let started = try makeTestSystemActionCommandHandler().startTimerMutation(
            taskID: child.id,
            container: context.container
        )
        let segmentID = try #require(started.subjectSegmentID)
        #expect(store.task(for: child.id) == nil)
        #expect(store.activeSegments.isEmpty)

        #expect(store.deleteSelectedTask(taskID: parent.id))

        let freshContext = ModelContext(context.container)
        let persistedTasks = try freshContext.fetch(FetchDescriptor<TaskNode>())
        let persistedSegments = try freshContext.fetch(FetchDescriptor<TimeSegment>())
        #expect(persistedTasks.first { $0.id == parent.id }?.deletedAt != nil)
        #expect(persistedTasks.first { $0.id == child.id }?.deletedAt != nil)
        #expect(persistedSegments.first { $0.id == segmentID }?.endedAt != nil)
        #expect(store.task(for: parent.id) == nil)
        #expect(store.task(for: child.id) == nil)
        #expect(store.activeSegments.isEmpty)
    }

    private func freshTaskRepository(
        _ container: ModelContainer
    ) -> SwiftDataTaskRepository {
        SwiftDataTaskRepository(
            context: ModelContext(container),
            deviceID: "test"
        )
    }
}
