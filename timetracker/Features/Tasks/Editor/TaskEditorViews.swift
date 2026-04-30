import SwiftUI

struct TaskEditorSheet: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: TaskEditorDraft

    var body: some View {
        TaskEditorPanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                store.taskEditorDraft = nil
                store.taskEditorReturnDestination = nil
                dismiss()
            },
            onSave: { draft in
                if store.saveTaskDraft(draft) {
                    dismiss()
                }
            }
        )
        .platformSheetFrame(width: 520, height: 620)
        .presentationDetents([.large])
    }
}

struct TaskEditorPanel: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draft: TaskEditorDraft
    @FocusState private var focusedChecklistDraftID: UUID?
    let onCancel: () -> Void
    let onSave: (TaskEditorDraft) -> Void

    private let colors = TaskColorPalette.hexValues

    init(store: TimeTrackerStore, initialDraft: TaskEditorDraft, onCancel: @escaping () -> Void, onSave: @escaping (TaskEditorDraft) -> Void) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        NavigationStack {
            TaskEditorForm(
                store: store,
                draft: $draft,
                colors: colors,
                focusedChecklistDraftID: $focusedChecklistDraftID,
                orderedChecklistIndices: orderedChecklistIndices,
                moveChecklistItem: { source, destination in
                    moveChecklistItem(from: source, to: destination)
                },
                addChecklistItem: { visualIndex in
                    addChecklistItem(afterVisualIndex: visualIndex)
                }
            )
            .navigationTitle(draft.taskID == nil ? AppStrings.localized("editor.task.newTitle") : AppStrings.localized("editor.task.editTitle"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel) {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        onSave(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var orderedChecklistIndices: [Int] {
        draft.checklistItems.indices.sorted { lhs, rhs in
            let left = draft.checklistItems[lhs]
            let right = draft.checklistItems[rhs]
            if left.isCompleted != right.isCompleted {
                return !left.isCompleted
            }
            return lhs < rhs
        }
    }

    private func moveChecklistItem(from source: Int, to destination: Int) {
        guard draft.checklistItems.indices.contains(source),
              draft.checklistItems.indices.contains(destination),
              draft.checklistItems[source].isCompleted == draft.checklistItems[destination].isCompleted else {
            return
        }
        var orderedDrafts = orderedChecklistIndices.map { draft.checklistItems[$0] }
        guard let sourceVisualIndex = orderedDrafts.firstIndex(where: { $0.id == draft.checklistItems[source].id }),
              let destinationVisualIndex = orderedDrafts.firstIndex(where: { $0.id == draft.checklistItems[destination].id }) else {
            return
        }
        orderedDrafts.swapAt(sourceVisualIndex, destinationVisualIndex)
        draft.checklistItems = orderedDrafts
    }

    private func moveChecklistItem(atVisualIndex visualIndex: Int, direction: Int) {
        let ordered = orderedChecklistIndices
        let targetVisualIndex = visualIndex + direction
        guard ordered.indices.contains(visualIndex),
              ordered.indices.contains(targetVisualIndex) else {
            return
        }
        moveChecklistItem(from: ordered[visualIndex], to: ordered[targetVisualIndex])
    }

    private func addChecklistItem(afterVisualIndex visualIndex: Int? = nil) {
        let newItem = ChecklistEditorDraft()
        var orderedDrafts = orderedChecklistIndices.map { draft.checklistItems[$0] }
        if let visualIndex,
           orderedDrafts.indices.contains(visualIndex),
           orderedDrafts[visualIndex].isCompleted == false {
            orderedDrafts.insert(newItem, at: visualIndex + 1)
        } else {
            let insertionIndex = orderedDrafts.firstIndex { $0.isCompleted } ?? orderedDrafts.count
            orderedDrafts.insert(newItem, at: insertionIndex)
        }
        draft.checklistItems = orderedDrafts
        focusedChecklistDraftID = newItem.id
    }

}
