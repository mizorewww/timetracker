import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedTaskLifecycleCommandCoordinatorTests {
    @Test
    func archiveCanonicalizesATimestampOnlyLegacyArchiveMarker() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Conflicting archive timestamp",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        task.statusRaw = LegacyTaskStatusRaw.active
        let archivedAt = Date(timeIntervalSinceReferenceDate: 100)
        task.archivedAt = archivedAt
        try context.save()
        let coordinator = StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            deviceID: "test"
        )

        let repaired = try coordinator.archive(taskID: task.id)

        #expect(repaired.didMutate)
        let fetchedTask = try freshTaskRepository(context.container).task(id: task.id)
        let freshTask = try #require(fetchedTask)
        #expect(freshTask.statusRaw == LegacyTaskStatusRaw.archived)
        #expect(freshTask.archivedAt == archivedAt)
        #expect(freshTask.isArchivedForLifecycle)

        let canonicalNoOp = try coordinator.archive(taskID: task.id)
        #expect(canonicalNoOp.didMutate == false)
    }

    @Test
    func archiveCanonicalizesARawOnlyLegacyArchiveMarker() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Raw-only archive",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        task.statusRaw = LegacyTaskStatusRaw.archived
        task.archivedAt = nil
        try context.save()
        let coordinator = StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            deviceID: "test"
        )

        let repaired = try coordinator.archive(taskID: task.id)

        #expect(repaired.didMutate)
        let fetchedTask = try freshTaskRepository(context.container).task(id: task.id)
        let freshTask = try #require(fetchedTask)
        #expect(freshTask.statusRaw == LegacyTaskStatusRaw.archived)
        #expect(freshTask.archivedAt != nil)
        #expect(freshTask.isArchivedForLifecycle)
    }

    @Test
    func unarchiveClearsEveryLegacyArchiveShapeWithoutRevivingStatusSemantics() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let canonical = try repository.createTask(
            title: "Canonical archive",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let rawOnly = try repository.createTask(
            title: "Raw-only archive",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let timestampOnly = try repository.createTask(
            title: "Timestamp-only archive",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let active = try repository.createTask(
            title: "Already active",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let deletedArchive = try repository.createTask(
            title: "Historical deletion",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        canonical.statusRaw = LegacyTaskStatusRaw.archived
        canonical.archivedAt = Date(timeIntervalSinceReferenceDate: 100)
        rawOnly.statusRaw = LegacyTaskStatusRaw.archived
        rawOnly.archivedAt = nil
        timestampOnly.statusRaw = LegacyTaskStatusRaw.completed
        timestampOnly.archivedAt = Date(timeIntervalSinceReferenceDate: 200)
        deletedArchive.archivedAt = Date(timeIntervalSinceReferenceDate: 300)
        deletedArchive.deletedAt = Date(timeIntervalSinceReferenceDate: 400)
        try context.save()
        let coordinator = StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            deviceID: "test"
        )

        #expect(try coordinator.unarchive(taskID: canonical.id).didMutate)
        #expect(try coordinator.unarchive(taskID: rawOnly.id).didMutate)
        #expect(try coordinator.unarchive(taskID: timestampOnly.id).didMutate)
        #expect(try coordinator.unarchive(taskID: active.id).didMutate == false)
        #expect(throws: TaskLifecycleMutationError.taskNotFound) {
            try coordinator.unarchive(taskID: deletedArchive.id)
        }

        let freshRepository = freshTaskRepository(context.container)
        let restoredCanonical = try #require(try freshRepository.task(id: canonical.id))
        let restoredRawOnly = try #require(try freshRepository.task(id: rawOnly.id))
        let restoredTimestampOnly = try #require(try freshRepository.task(id: timestampOnly.id))
        let verificationContext = ModelContext(context.container)
        let preservedDeletion = try #require(
            try verificationContext.fetch(FetchDescriptor<TaskNode>())
                .first { $0.id == deletedArchive.id }
        )
        #expect(restoredCanonical.archivedAt == nil)
        #expect(restoredCanonical.statusRaw == LegacyTaskStatusRaw.active)
        #expect(restoredCanonical.isArchivedForLifecycle == false)
        #expect(restoredRawOnly.archivedAt == nil)
        #expect(restoredRawOnly.statusRaw == LegacyTaskStatusRaw.active)
        #expect(restoredTimestampOnly.archivedAt == nil)
        #expect(restoredTimestampOnly.statusRaw == LegacyTaskStatusRaw.completed)
        #expect(preservedDeletion.archivedAt == Date(timeIntervalSinceReferenceDate: 300))
        #expect(preservedDeletion.deletedAt == Date(timeIntervalSinceReferenceDate: 400))
    }

    @Test
    func recoveryRestoresAnArchivedHierarchyAsOneCommandOutcome() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let root = try repository.createTask(
            title: "Root",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Child",
            parentID: root.id,
            colorHex: nil,
            iconName: nil
        )
        let leaf = try repository.createTask(
            title: "Leaf",
            parentID: child.id,
            colorHex: nil,
            iconName: nil
        )
        try repository.archiveTask(taskID: leaf.id)
        try repository.archiveTask(taskID: child.id)
        try repository.archiveTask(taskID: root.id)

        let outcome = try StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            deviceID: "test"
        ).restoreArchivedHierarchy(taskID: leaf.id)

        #expect(outcome.restoredTaskIDs == [root.id, child.id, leaf.id])
        #expect(outcome.events.count == 3)
        let freshRepository = freshTaskRepository(context.container)
        #expect(
            try [root.id, child.id, leaf.id].allSatisfy { taskID in
                try freshRepository.task(id: taskID)?
                    .isArchivedForLifecycle == false
            }
        )
    }

    @Test
    func recoveryDoesNotPartiallyRestoreWhenAnAncestorIsMissing() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let root = try repository.createTask(
            title: "Deleted root",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Preserved child",
            parentID: root.id,
            colorHex: nil,
            iconName: nil
        )
        try repository.archiveTask(taskID: child.id)
        root.deletedAt = Date()
        try context.save()

        let coordinator = StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            deviceID: "test"
        )
        #expect(throws: TaskLifecycleMutationError.parentUnavailable) {
            try coordinator.restoreArchivedHierarchy(taskID: child.id)
        }

        let preservedChild = try #require(
            try freshTaskRepository(context.container).task(id: child.id)
        )
        #expect(preservedChild.isArchivedForLifecycle)
    }

    @Test
    func storeUnarchivesNestedExplicitArchivesTopDownWithoutChangingSelection() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let archivedParent = try repository.createTask(
            title: "Archived parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let ordinaryChild = try repository.createTask(
            title: "Ordinary child",
            parentID: archivedParent.id,
            colorHex: nil,
            iconName: nil
        )
        let explicitlyArchivedChild = try repository.createTask(
            title: "Explicitly archived child",
            parentID: archivedParent.id,
            colorHex: nil,
            iconName: nil
        )
        let selected = try repository.createTask(
            title: "Current selection",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try repository.archiveTask(taskID: explicitlyArchivedChild.id)
        try repository.archiveTask(taskID: archivedParent.id)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.selectedTaskID = selected.id

        let coordinator = StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            deviceID: "test"
        )
        #expect(throws: TaskLifecycleMutationError.archivedAncestorMustRestoreFirst) {
            try coordinator.unarchive(taskID: explicitlyArchivedChild.id)
        }

        #expect(store.unarchiveTask(taskID: archivedParent.id))

        let restored = try #require(try freshTaskRepository(context.container).task(id: archivedParent.id))
        #expect(restored.isArchivedForLifecycle == false)
        #expect(store.isTaskVisible(restored))
        #expect(store.isTaskVisible(ordinaryChild))
        #expect(store.isTaskVisible(explicitlyArchivedChild) == false)
        #expect(store.archivedTasks.map(\.id) == [explicitlyArchivedChild.id])
        #expect(store.selectedTaskID == selected.id)

        #expect(store.unarchiveTask(taskID: explicitlyArchivedChild.id))
        #expect(store.isTaskVisible(explicitlyArchivedChild))
        #expect(store.archivedTasks.isEmpty)
        #expect(store.selectedTaskID == selected.id)
    }

    @Test
    func unarchiveRepairsSelfAndTwoTaskCyclesWithoutDeadlockingRecovery() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let selfCycle = try repository.createTask(
            title: "Self cycle",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let first = try repository.createTask(
            title: "First",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let second = try repository.createTask(
            title: "Second",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        selfCycle.parentID = selfCycle.id
        first.parentID = second.id
        second.parentID = first.id
        try context.save()
        try repository.archiveTask(taskID: selfCycle.id)
        try repository.archiveTask(taskID: first.id)
        try repository.archiveTask(taskID: second.id)

        let repairPlan = TaskHierarchyRepairPlan(tasks: [first, second])
        let cycleBreakerID = try #require(repairPlan.cycleBreakerTaskIDs.first)
        let blockedTaskID = try #require(
            [first.id, second.id].first { $0 != cycleBreakerID }
        )
        let coordinator = StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            deviceID: "test"
        )

        #expect(try coordinator.unarchive(taskID: selfCycle.id).didMutate)
        #expect(throws: TaskLifecycleMutationError.archivedAncestorMustRestoreFirst) {
            try coordinator.unarchive(taskID: blockedTaskID)
        }
        #expect(try coordinator.unarchive(taskID: cycleBreakerID).didMutate)
        #expect(try coordinator.unarchive(taskID: blockedTaskID).didMutate)
    }

    @Test
    func staleSceneCannotArchiveSubtreeStartedBySiblingContext() throws {
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

        #expect(store.archiveSelectedTask(taskID: parent.id) == false)
        let persisted = try #require(
            try freshTaskRepository(context.container).task(id: parent.id)
        )
        #expect(persisted.statusRaw == LegacyTaskStatusRaw.active)
        #expect(persisted.archivedAt == nil)
        #expect(store.errorMessage == AppStrings.localized("task.action.archive.stopFirst"))
    }

    @Test
    func staleSceneCanArchiveAfterSiblingContextStopsTimer() throws {
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

        #expect(store.archiveSelectedTask(taskID: task.id))
        let persisted = try #require(
            try freshTaskRepository(context.container).task(id: task.id)
        )
        #expect(persisted.statusRaw == LegacyTaskStatusRaw.archived)
        #expect(persisted.archivedAt != nil)
        #expect(persisted.isArchivedForLifecycle)
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
        let persisted = try #require(
            try freshTaskRepository(context.container).task(id: task.id)
        )
        #expect(persisted.statusRaw == LegacyTaskStatusRaw.active)
        #expect(persisted.archivedAt == nil)
        #expect(store.errorMessage == AppStrings.localized("task.action.archive.stopFirst"))
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
