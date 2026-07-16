import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreCompletedTaskSemanticsTests {
    @Test @MainActor
    func completedBranchStaysInTreeAndHistoryButLeavesWorkCandidates() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try repository.createTask(
            title: "Completed project",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Historical child",
            parentID: parent.id,
            colorHex: nil,
            iconName: nil
        )
        let activeRoot = try repository.createTask(
            title: "Current work",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try repository.setTaskStatus(taskID: parent.id, status: .completed)

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(store.visibleTaskIDs.isSuperset(of: [parent.id, child.id, activeRoot.id]))
        #expect(store.trackableTaskIDs.contains(parent.id) == false)
        #expect(store.trackableTaskIDs.contains(child.id) == false)
        #expect(store.trackableTaskIDs.contains(activeRoot.id))
        #expect(store.rootTasks().contains { $0.id == parent.id })
        #expect(store.children(of: parent).contains { $0.id == child.id })

        let rows = store.taskTreeRows(expandedTaskIDs: [parent.id])
        #expect(rows.contains { $0.taskID == parent.id })
        #expect(rows.contains { $0.taskID == child.id })
        #expect(store.frequentRecentTasks(limit: 20).contains { $0.id == child.id } == false)
        #expect(store.watchStateSnapshot().recentTasks.contains { $0.taskID == child.id } == false)
    }

    @Test @MainActor
    func completedBranchRejectsFacadeNewWorkAndInboxTargets() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try repository.createTask(
            title: "Completed project",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Blocked child",
            parentID: parent.id,
            colorHex: nil,
            iconName: nil
        )
        try repository.setTaskStatus(taskID: parent.id, status: .completed)
        let inboxItem = InboxItem(title: "Route this", deviceID: "test")
        context.insert(inboxItem)
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        store.startTask(child)
        #expect(store.activeSegments.isEmpty)

        var manualDraft = ManualTimeDraft(taskID: child.id, tasks: [child])
        manualDraft.startedAt = Date().addingTimeInterval(-600)
        manualDraft.endedAt = Date()
        #expect(store.saveManualTimeDraft(manualDraft) == false)

        store.selectTask(child.id, revealInToday: false)
        store.startPomodoroForSelectedTask(focusSeconds: 60, breakSeconds: 60)
        #expect(store.pomodoroRuns.isEmpty)

        let presentationRouter = AppPresentationRouter()
        #expect(presentationRouter.presentNewTask(
            using: store,
            parentID: child.id,
            preservingDestination: .tasks
        ) == false)
        #expect(presentationRouter.sheet == nil)

        var suggestionDraft = InboxSuggestionEditorDraft(
            item: inboxItem,
            fallbackTaskID: child.id
        )
        suggestionDraft.taskID = child.id
        #expect(store.saveInboxSuggestionDraft(suggestionDraft) == false)
    }

    @Test @MainActor
    func staleSystemAndWatchStartsRejectCompletedTasks() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(
            title: "Completed",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try repository.setTaskStatus(taskID: task.id, status: .completed)

        #expect(throws: SystemActionCommandError.taskNotFound) {
            try makeTestSystemActionCommandHandler().startTimer(
                taskID: task.id,
                allowParallelTimers: true,
                context: context
            )
        }

        let watchCommand = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: task.id,
            segmentID: nil,
            issuedAt: Date(),
            deviceID: "watch"
        )
        #expect(throws: SystemActionCommandError.taskNotFound) {
            try makeTestWatchCommandProcessor(receiptStore: InMemoryWatchCommandReceiptStore()).process(
                watchCommand,
                allowParallelTimers: true,
                context: context
            )
        }
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        #expect(try timeRepository.activeSegments().isEmpty)
    }

    @Test @MainActor
    func completingOrArchivingSubtreeRequiresStoppingEveryActiveTimer() throws {
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

        store.setTaskStatus(.completed, taskID: parent.id)
        #expect(try taskRepository.task(id: parent.id)?.status == .active)
        #expect(store.errorMessage == AppStrings.localized("task.action.complete.stopFirst"))

        var draft = store.editorDraft(for: parent)
        draft.status = .completed
        #expect(store.saveTaskDraft(draft) == false)
        #expect(store.errorMessage == AppStrings.localized("task.action.complete.stopFirst"))

        store.archiveSelectedTask(taskID: parent.id)
        #expect(try taskRepository.task(id: parent.id)?.status == .active)
        #expect(store.errorMessage == AppStrings.localized("task.action.archive.stopFirst"))

        store.stop(segment: segment)
        #expect(try timeRepository.activeSegments().isEmpty)
        store.setTaskStatus(.completed, taskID: parent.id)
        #expect(try taskRepository.task(id: parent.id)?.status == .completed)
    }

    @Test @MainActor
    func taskEditorCanMoveAnActiveChildOutOfACompletedBranchButNotTheCompletedTask() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let completedParent = try repository.createTask(
            title: "Completed parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let activeChild = try repository.createTask(
            title: "Recoverable child",
            parentID: completedParent.id,
            colorHex: nil,
            iconName: nil
        )
        let destination = try repository.createTask(
            title: "Available destination",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        try repository.setTaskStatus(taskID: completedParent.id, status: .completed)

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(store.parentChangeBlocker(for: activeChild) == nil)
        #expect(store.validParentTasks(for: activeChild.id).map(\.id) == [destination.id])

        var childDraft = store.editorDraft(for: activeChild)
        childDraft.parentID = destination.id
        #expect(store.saveTaskDraft(childDraft))
        #expect(try repository.task(id: activeChild.id)?.parentID == destination.id)

        var completedDraft = store.editorDraft(for: completedParent)
        completedDraft.parentID = destination.id
        #expect(store.saveTaskDraft(completedDraft) == false)
        #expect(store.errorMessage == AppStrings.localized("task.parent.completedLocked"))
        #expect(try repository.task(id: completedParent.id)?.parentID == nil)
    }

    @Test @MainActor
    func existingTimerUnderNewlyCompletedBranchRemainsVisibleAndStoppable() throws {
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
        // Simulate a status arriving from another device while this timer is
        // already running locally.
        try taskRepository.setTaskStatus(taskID: parent.id, status: .completed)

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(store.isTaskVisible(child))
        #expect(store.isTaskAvailableForTracking(child) == false)
        #expect(store.activeSegments.contains { $0.id == segment.id })

        store.stop(segment: segment)
        #expect(try timeRepository.activeSegments().isEmpty)
        #expect(store.isTaskVisible(child))
    }

    @Test @MainActor
    func reopenActionRestoresEveryCompletedBlockerOnThePath() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try repository.createTask(
            title: "Completed parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Completed child",
            parentID: parent.id,
            colorHex: nil,
            iconName: nil
        )
        let grandchild = try repository.createTask(
            title: "Blocked grandchild",
            parentID: child.id,
            colorHex: nil,
            iconName: nil
        )
        try repository.setTaskStatus(taskID: parent.id, status: .completed)
        try repository.setTaskStatus(taskID: child.id, status: .completed)

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.completedWorkBlockers(for: grandchild).map(\.id) == [parent.id, child.id])

        store.reopenTaskForWork(grandchild.id)

        #expect(try repository.task(id: parent.id)?.status == .active)
        #expect(try repository.task(id: child.id)?.status == .active)
        #expect(store.isTaskAvailableForTracking(grandchild))
    }
}
