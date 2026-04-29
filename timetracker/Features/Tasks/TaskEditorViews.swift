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

    private let colors = ["1677FF", "16A34A", "7C3AED", "F97316", "EF4444", "0EA5E9", "64748B"]

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
              draft.checklistItems.indices.contains(destination) else {
            return
        }
        draft.checklistItems.swapAt(source, destination)
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
        if let visualIndex {
            let insertionIndex = min(visualIndex + 1, draft.checklistItems.count)
            draft.checklistItems.insert(newItem, at: insertionIndex)
        } else {
            draft.checklistItems.append(newItem)
        }
        focusedChecklistDraftID = newItem.id
    }
}
