import Foundation
import Testing

@Suite(.serialized)
struct TaskWorkspaceContractTests {
    @Test
    func existingTaskEditingStaysInsideTheCanonicalTaskWorkspace() throws {
        let detail = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailView.swift"
        )
        let navigation = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailNavigationViews.swift"
        )
        let taskNavigation = try sourceText(
            "timetracker/Features/Tasks/Management/TasksNavigationView.swift"
        )
        let actions = try sourceText(
            "timetracker/Features/Tasks/Management/TaskRowComponents.swift"
        )
        let selection = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+Selection.swift"
        )
        let route = try sourceText("timetracker/Stores/Navigation/TasksRoute.swift")
        let router = try sourceText("timetracker/App/AppPresentationRouter.swift")

        #expect(detail.contains("@State private var editorDraft: TaskEditorDraft?"))
        #expect(detail.contains("TaskEditorPanel("))
        #expect(detail.contains("editorDraft = store.editorDraft(for: task)"))
        #expect(detail.contains("store.saveTaskDraftResult("))
        #expect(detail.contains("finishEditing()"))
        #expect(navigation.contains("let isEditing: Bool"))
        #expect(navigation.contains("let beginEditing: (TaskNode) -> Void"))
        #expect(navigation.contains("presentationRouter.presentEditTask") == false)
        #expect(taskNavigation.contains("startsEditing: route.startsEditing"))
        #expect(actions.contains("store.openTaskEditor(task.id)"))
        #expect(actions.contains("presentEditTask") == false)
        #expect(selection.contains("func openTaskEditor(_ taskID: UUID)"))
        #expect(route.contains("case editor(taskID: UUID)"))
        #expect(route.contains("var startsEditing: Bool"))
        #expect(router.contains("func presentEditTask(") == false)
    }

    @Test
    func theSharedEditorSessionWorksInSheetsAndNavigationDestinations() throws {
        let editor = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorViews.swift"
        )

        #expect(editor.contains("struct TaskEditorSheet: View"))
        #expect(editor.contains("NavigationStack {\n            TaskEditorPanel("))
        #expect(editor.contains("struct TaskEditorPanel: View"))
        #expect(editor.components(separatedBy: "NavigationStack {").count - 1 == 1)
        #expect(editor.contains(".navigationBarBackButtonHidden(true)"))
        #expect(editor.contains("pendingReloadDraft = store.editorDraft(for: latestTask)"))
        #expect(editor.contains("sessionBaseline = latestDraft"))
        #expect(editor.contains(".editorDiscardConfirmation("))
    }
}
