import SwiftUI

struct TaskEditorSheet: View {
    let store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: TaskEditorDraft
    let returnDestination: TimeTrackerStore.DesktopDestination

    var body: some View {
        TaskEditorPanel(
            store: store,
            initialDraft: initialDraft,
            onCancel: {
                dismiss()
            },
            onSave: { draft in
                if store.saveTaskDraft(draft, returnDestination: returnDestination) {
                    dismiss()
                }
            }
        )
        .platformSheetFrame(width: 520, height: 620)
        .presentationDetents([.large])
    }
}

struct TaskEditorPanel: View {
    let store: TimeTrackerStore
    @State private var draft: TaskEditorDraft
    @FocusState private var focusedChecklistDraftID: UUID?
    @State private var isDiscardConfirmationPresented = false
    let initialDraft: TaskEditorDraft
    let onCancel: () -> Void
    let onSave: (TaskEditorDraft) -> Void
    let parentCandidates: [TaskNode]

    private let colors = TaskColorPalette.hexValues

    init(store: TimeTrackerStore, initialDraft: TaskEditorDraft, onCancel: @escaping () -> Void, onSave: @escaping (TaskEditorDraft) -> Void) {
        self.store = store
        self.initialDraft = initialDraft
        self.onCancel = onCancel
        self.onSave = onSave
        var candidates = store.validParentTasks(for: initialDraft.taskID)
        if let currentParentID = initialDraft.parentID,
           let currentParent = store.task(for: currentParentID),
           candidates.contains(where: { $0.id == currentParentID }) == false {
            candidates.append(currentParent)
        }
        parentCandidates = candidates
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        let validation = TaskEditorValidation(
            title: draft.title,
            notes: draft.notes,
            iconName: draft.iconName,
            colorHex: draft.colorHex
        )

        NavigationStack {
            TaskEditorForm(
                store: store,
                draft: $draft,
                validation: validation,
                colors: colors,
                parentCandidates: parentCandidates,
                focusedChecklistDraftID: $focusedChecklistDraftID,
                orderedChecklistIndices: orderedChecklistIndices,
                moveChecklistItems: { sourceOffsets, destination in
                    moveChecklistItems(fromOffsets: sourceOffsets, toOffset: destination)
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
                        requestCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("task.editor.cancel")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        onSave(draft)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave(validation))
                    .accessibilityIdentifier("task.editor.save")
                }
            }
        }
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: draft != initialDraft,
            discard: onCancel
        )
    }

    private func canSave(_ validation: TaskEditorValidation) -> Bool {
        validation.isValid && !isBlockedCompletionTransition
    }

    private var isBlockedCompletionTransition: Bool {
        guard let taskID = draft.taskID,
              draft.status == .completed,
              initialDraft.status != .completed else {
            return false
        }
        return store.hasActiveTimer(inTaskSubtree: taskID)
    }

    private func requestCancel() {
        if draft == initialDraft {
            onCancel()
        } else {
            isDiscardConfirmationPresented = true
        }
    }

    private var orderedChecklistIndices: [Int] {
        let indices = draft.checklistItems.indices
        return indices.filter { !draft.checklistItems[$0].isCompleted }
            + indices.filter { draft.checklistItems[$0].isCompleted }
    }

    private func moveChecklistItems(fromOffsets sourceOffsets: IndexSet, toOffset destination: Int) {
        let orderedDrafts = orderedChecklistIndices.map { draft.checklistItems[$0] }
        let elements = orderedDrafts.map {
            ChecklistOrderingElement(id: $0.id, isCompleted: $0.isCompleted)
        }
        guard let reorderedIDs = ChecklistOrderingService().reorderedIDs(
            elements: elements,
            sourceOffsets: sourceOffsets,
            destination: destination
        ) else {
            return
        }

        let draftByID = draft.checklistItems.reduce(into: [UUID: ChecklistEditorDraft]()) { result, item in
            result[item.id] = item
        }
        draft.checklistItems = reorderedIDs.compactMap { draftByID[$0] }
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
