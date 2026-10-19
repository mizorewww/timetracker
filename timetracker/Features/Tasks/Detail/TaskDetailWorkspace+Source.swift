import Foundation

extension TaskDetailWorkspace {
    var editorSourceToken: TaskEditorSourceToken? {
        guard let task = store.task(for: taskID) else { return nil }
        return TaskEditorSourceToken(
            baseline: store.editorDraft(for: task).baseline,
            parentCandidateIDs: store.validParentTasks(for: taskID).map(\.id)
        )
    }

    func reloadLatestDraft() {
        session.reloadLatestDraft()
        clearInputFocus()
    }

    func clearInputFocus() {
        focusedTextField = nil
        focusedChecklistDraftID = nil
    }
}

struct TaskEditorSourceToken: Equatable {
    let baseline: TaskEditorDraftBaseline?
    let parentCandidateIDs: [UUID]
}
