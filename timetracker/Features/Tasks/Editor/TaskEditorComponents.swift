import SwiftUI

struct TaskEditorForm: View {
    let store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    let colors: [String]
    let parentCandidates: [TaskNode]
    let focusedChecklistDraftID: FocusState<UUID?>.Binding
    let orderedChecklistIndices: [Int]
    let moveChecklistItems: (IndexSet, Int) -> Void
    let addChecklistItem: (Int?) -> Void

    var body: some View {
        Form {
            TaskInfoEditorSection(
                store: store,
                draft: $draft,
                colors: colors,
                parentCandidates: parentCandidates
            )
            TaskPlanEditorSection(draft: $draft)
            TaskChecklistEditorSection(
                checklistItems: $draft.checklistItems,
                focusedChecklistDraftID: focusedChecklistDraftID,
                orderedChecklistIndices: orderedChecklistIndices,
                moveChecklistItems: moveChecklistItems,
                addChecklistItem: addChecklistItem
            )
            TaskNotesEditorSection(notes: $draft.notes)
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("task.editor")
    }
}
