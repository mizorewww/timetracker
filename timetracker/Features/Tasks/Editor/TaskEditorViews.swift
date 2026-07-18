import SwiftUI

struct TaskEditorSheet: View {
    let store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    let initialDraft: TaskEditorDraft
    let returnDestination: TimeTrackerStore.DesktopDestination

    var body: some View {
        NavigationStack {
            TaskEditorPanel(
                store: store,
                initialDraft: initialDraft,
                onCancel: {
                    dismiss()
                },
                onSave: { draft in
                    store.saveTaskDraftResult(
                        draft,
                        returnDestination: returnDestination
                    )
                },
                onSaved: { dismiss() }
            )
        }
        .platformSheetFrame(width: 520, height: 620)
        .presentationDetents([.large])
    }
}

struct TaskEditorPanel: View {
    let store: TimeTrackerStore
    @State private var draft: TaskEditorDraft
    @State private var sessionBaseline: TaskEditorDraft
    @State private var parentCandidates: [TaskNode]
    @State private var pendingReloadDraft: TaskEditorDraft?
    @FocusState private var focusedChecklistDraftID: UUID?
    @State private var isDiscardConfirmationPresented = false
    let onCancel: () -> Void
    let onSave: (TaskEditorDraft) -> TaskDraftSaveResult
    let onSaved: () -> Void

    init(
        store: TimeTrackerStore,
        initialDraft: TaskEditorDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (TaskEditorDraft) -> TaskDraftSaveResult,
        onSaved: @escaping () -> Void
    ) {
        self.store = store
        self.onCancel = onCancel
        self.onSave = onSave
        self.onSaved = onSaved
        _draft = State(initialValue: initialDraft)
        _sessionBaseline = State(initialValue: initialDraft)
        _parentCandidates = State(
            initialValue: Self.parentCandidates(for: initialDraft, store: store)
        )
    }

    var body: some View {
        let validation = TaskEditorValidation(
            title: draft.title,
            notes: draft.notes,
            iconName: draft.iconName,
            colorHex: draft.colorHex
        )

        TaskEditorForm(
            store: store,
            draft: $draft,
            validation: validation,
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
        .navigationTitle(
            draft.taskID == nil
                ? AppStrings.localized("editor.task.newTitle")
                : AppStrings.localized("editor.task.editTitle")
        )
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationBarBackButtonHidden(true)
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
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave(validation))
                .accessibilityIdentifier("task.editor.save")
            }
        }
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: draft != sessionBaseline,
            discard: onCancel
        )
        .alert(
            AppStrings.localized("task.editor.stale.title"),
            isPresented: reloadAlertBinding
        ) {
            Button(
                AppStrings.localized("task.editor.stale.reload"),
                role: .destructive,
                action: reloadLatestDraft
            )
            Button(AppStrings.localized("task.editor.stale.keepEditing"), role: .cancel) {
                pendingReloadDraft = nil
            }
        } message: {
            Text(.app("task.editor.stale.reloadMessage"))
        }
    }

    private func canSave(_ validation: TaskEditorValidation) -> Bool {
        validation.isValid
    }

    private func requestCancel() {
        if draft == sessionBaseline {
            onCancel()
        } else {
            isDiscardConfirmationPresented = true
        }
    }

    private func save() {
        switch onSave(draft) {
        case .saved:
            onSaved()
        case .stale:
            guard let taskID = draft.taskID,
                  let latestTask = store.task(for: taskID) else {
                store.errorMessage = AppStrings.localized("systemAction.error.taskNotFound")
                return
            }
            pendingReloadDraft = store.editorDraft(for: latestTask)
        case .failed(let message):
            store.errorMessage = message
        }
    }

    private var reloadAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingReloadDraft != nil },
            set: { isPresented in
                if isPresented == false {
                    pendingReloadDraft = nil
                }
            }
        )
    }

    private func reloadLatestDraft() {
        guard let latestDraft = pendingReloadDraft else { return }
        draft = latestDraft
        sessionBaseline = latestDraft
        parentCandidates = Self.parentCandidates(for: latestDraft, store: store)
        focusedChecklistDraftID = nil
        pendingReloadDraft = nil
    }

    private static func parentCandidates(
        for draft: TaskEditorDraft,
        store: TimeTrackerStore
    ) -> [TaskNode] {
        var candidates = store.validParentTasks(for: draft.taskID)
        if let currentParentID = draft.parentID,
           let currentParent = store.task(for: currentParentID),
           candidates.contains(where: { $0.id == currentParentID }) == false {
            candidates.append(currentParent)
        }
        return candidates
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
