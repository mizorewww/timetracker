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
