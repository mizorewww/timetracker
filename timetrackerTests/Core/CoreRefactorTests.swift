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
        store.selectTask(task.id, revealInToday: false)

        store.deleteSelectedTask(taskID: task.id)

        #expect(store.desktopDestination == .tasks)
        #expect(store.selectedTaskID == nil)
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

}
