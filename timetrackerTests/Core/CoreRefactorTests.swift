import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreRefactorTests {
    @Test @MainActor
    func deletingSelectedTaskPreservesCurrentDestination() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Delete in Tasks", parentID: nil, colorHex: nil, iconName: nil)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.desktopDestination = .tasks
        store.openTaskDetail(task.id)

        store.deleteSelectedTask(taskID: task.id)

        #expect(store.desktopDestination == .tasks)
        #expect(store.selectedTaskID == nil)
        #expect(store.desktopTaskDetailID == nil)
    }

    @Test @MainActor
    func desktopTaskDetailNavigationIsSeparateFromPlainTaskSelection() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let detailTask = try taskRepository.createTask(title: "Open detail", parentID: nil, colorHex: nil, iconName: nil)
        let selectedTask = try taskRepository.createTask(title: "Plain selection", parentID: nil, colorHex: nil, iconName: nil)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.desktopDestination = .analytics

        store.openTaskDetail(detailTask.id)

        #expect(store.desktopDestination == .tasks)
        #expect(store.selectedTaskID == detailTask.id)
        #expect(store.desktopTaskDetailID == detailTask.id)

        store.closeTaskDetailNavigation()
        store.selectTask(selectedTask.id, revealInToday: false)

        #expect(store.desktopDestination == .tasks)
        #expect(store.selectedTaskID == selectedTask.id)
        #expect(store.desktopTaskDetailID == nil)

        store.openTaskDetail(detailTask.id)
        store.selectTask(selectedTask.id)

        #expect(store.desktopDestination == .today)
        #expect(store.selectedTaskID == selectedTask.id)
        #expect(store.desktopTaskDetailID == nil)
    }

    @Test @MainActor
    func taskPageDeleteCanPreserveTasksDestinationEvenAfterSelectionRevealedToday() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Delete from row", parentID: nil, colorHex: nil, iconName: nil)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.desktopDestination = .today
        store.selectTask(task.id)

        store.deleteSelectedTask(taskID: task.id, preservingDestination: .tasks)

        #expect(store.desktopDestination == .tasks)
        #expect(store.selectedTaskID == nil)
    }

    @Test @MainActor
    func taskPageCreatePreservesTasksDestinationAfterSelectingNewTask() throws {
        let context = try makeTestContext()
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.desktopDestination = .tasks
        store.presentNewTask(preservingDestination: .tasks)
        var draft = try #require(store.taskEditorDraft)
        draft.title = "Created from Tasks"

        store.saveTaskDraft(draft)

        #expect(store.desktopDestination == .tasks)
        #expect(store.selectedTask?.title == "Created from Tasks")
        #expect(store.taskEditorDraft == nil)
        #expect(store.taskEditorReturnDestination == nil)
    }

    @Test @MainActor
    func archivingAParentIsBlockedWhileItsChildTimerIsRunning() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let parent = try taskRepository.createTask(title: "Parent", parentID: nil, colorHex: nil, iconName: nil)
        let child = try taskRepository.createTask(title: "Child", parentID: parent.id, colorHex: nil, iconName: nil)
        _ = try timeRepository.startTask(taskID: child.id, source: .timer)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        store.archiveSelectedTask(taskID: parent.id)

        #expect(try taskRepository.task(id: parent.id)?.status == .active)
        #expect(store.errorMessage == AppStrings.localized("task.action.archive.stopFirst"))
        #expect(store.activeSegments.contains { $0.taskID == child.id })
    }

    @Test @MainActor
    func archivingAParentIsBlockedDuringAChildPomodoroBreakWithoutAnActiveSegment() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let parent = try taskRepository.createTask(title: "Parent", parentID: nil, colorHex: nil, iconName: nil)
        let child = try taskRepository.createTask(title: "Child", parentID: parent.id, colorHex: nil, iconName: nil)
        let run = PomodoroRun(taskID: child.id, deviceID: "test")
        run.state = .shortBreak
        run.startedAt = Date()
        context.insert(run)
        try context.save()
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        store.setTaskStatus(.archived, taskID: parent.id)

        #expect(try taskRepository.task(id: parent.id)?.status == .active)
        #expect(store.errorMessage == AppStrings.localized("task.action.archive.stopFirst"))
    }

    @Test @MainActor
    func manualTimeCannotBeAddedToAChildOfAnArchivedTask() {
        let parent = TaskNode(title: "Archived parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Hidden child", parentID: parent.id, deviceID: "test")
        parent.status = .archived
        let store = TimeTrackerStore()
        store.tasks = [parent, child]
        var draft = ManualTimeDraft(taskID: child.id, tasks: [child])
        draft.startedAt = Date().addingTimeInterval(-600)
        draft.endedAt = Date()

        #expect(store.saveManualTimeDraft(draft) == false)
        #expect(store.errorMessage == AppStrings.localized("task.archived.trackingUnavailable"))
    }

    @Test @MainActor
    func facadeCommandsExposeTypedUserVisibleErrors() {
        let store = TimeTrackerStore()
        let now = Date(timeIntervalSince1970: 1_000)

        var missingTaskDraft = ManualTimeDraft(taskID: nil, tasks: [])
        missingTaskDraft.startedAt = now
        missingTaskDraft.endedAt = now.addingTimeInterval(600)
        store.saveManualTimeDraft(missingTaskDraft)
        #expect(store.errorMessage == AppStrings.localized("task.selectRequired"))

        var invalidRangeDraft = ManualTimeDraft(taskID: UUID(), tasks: [])
        invalidRangeDraft.startedAt = now
        invalidRangeDraft.endedAt = now
        store.saveManualTimeDraft(invalidRangeDraft)
        #expect(store.errorMessage == AppStrings.localized("time.endAfterStart"))

        store.selectedTaskID = nil
        store.startPomodoroForSelectedTask()
        #expect(store.errorMessage == AppStrings.localized("task.selectBeforePomodoro"))
    }

    @Test @MainActor
    func committedMutationIsNotReportedAsFailedWhenPostCommitRefreshFails() throws {
        let context = try makeTestContext()
        let credentialStore = RefreshFailingCredentialStore()
        let store = TimeTrackerStore(llmCredentialStore: credentialStore)
        store.configureIfNeeded(context: context)
        credentialStore.shouldFailReads = true
        var didRunMutation = false

        let didCommit = store.perform(event: .preferenceChanged(key: "test")) {
            didRunMutation = true
        }

        #expect(didRunMutation)
        #expect(didCommit)
        #expect(store.errorMessage?.contains(RefreshFailingCredentialStore.failureMessage) == true)
    }

    @Test @MainActor
    func keychainMutationRemainsCommittedWhenItsPostCommitRefreshFails() throws {
        let context = try makeTestContext()
        let credentialStore = RefreshFailingCredentialStore()
        let store = TimeTrackerStore(llmCredentialStore: credentialStore)
        store.configureIfNeeded(context: context)
        credentialStore.shouldFailReads = true

        store.setLLMAPIKey("durable-secret")

        #expect(credentialStore.writtenAPIKey == "durable-secret")
        #expect(store.errorMessage?.contains(RefreshFailingCredentialStore.failureMessage) == true)
    }

    @Test @MainActor
    func failedMultiStepMutationRollsBackEarlierNestedSaves() throws {
        let context = try makeTestContext()
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        let didCommit = store.perform(event: .inboxChanged(itemIDs: [])) {
            try InboxCommandHandler().add(
                title: "Must roll back",
                existingItems: [],
                context: context
            )
            throw ForcedMutationFailure()
        }

        #expect(!didCommit)
        #expect(try context.fetch(FetchDescriptor<InboxItem>()).isEmpty)
    }

}

private struct ForcedMutationFailure: Error {}

private final class RefreshFailingCredentialStore: LLMCredentialStoring {
    static let failureMessage = "Injected credential refresh failure"
    var shouldFailReads = false
    private(set) var writtenAPIKey: String?

    func readAPIKey() throws -> String? {
        if shouldFailReads {
            throw Failure()
        }
        return nil
    }

    func writeAPIKey(_ apiKey: String) throws {
        writtenAPIKey = apiKey
    }

    private struct Failure: LocalizedError {
        var errorDescription: String? {
            RefreshFailingCredentialStore.failureMessage
        }
    }
}
