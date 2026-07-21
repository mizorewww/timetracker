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
    @State private var session: TaskEditorSession
    @FocusState private var focusedTextField: TaskEditorTextField?
    @FocusState private var focusedChecklistDraftID: UUID?
    let isInteractionDisabled: Bool
    let onCancel: () -> Void
    let onSave: (TaskEditorDraft) -> TaskDraftSaveResult
    let onSaved: () -> Void

    init(
        store: TimeTrackerStore,
        initialDraft: TaskEditorDraft,
        isInteractionDisabled: Bool = false,
        onCancel: @escaping () -> Void,
        onSave: @escaping (TaskEditorDraft) -> TaskDraftSaveResult,
        onSaved: @escaping () -> Void
    ) {
        self.store = store
        self.isInteractionDisabled = isInteractionDisabled
        self.onCancel = onCancel
        self.onSave = onSave
        self.onSaved = onSaved
        _session = State(
            initialValue: TaskEditorSession(
                store: store,
                initialDraft: initialDraft
            )
        )
    }

    var body: some View {
        @Bindable var session = session

        TaskEditorForm(
            store: store,
            draft: $session.draft,
            validation: session.validation,
            parentCandidates: session.parentCandidates,
            focusedTextField: $focusedTextField,
            focusedChecklistDraftID: $focusedChecklistDraftID,
            orderedChecklistIndices: session.orderedChecklistIndices,
            toggleChecklistItem: { id in
                session.toggleChecklistItem(id: id)
            },
            moveChecklistItems: { sourceOffsets, destination in
                session.moveChecklistItems(
                    fromOffsets: sourceOffsets,
                    toOffset: destination
                )
            },
            addChecklistItem: { visualIndex in
                focusedChecklistDraftID = session.addChecklistItem(
                    afterVisualIndex: visualIndex
                )
            }
        )
        .disabled(isInteractionDisabled)
        .navigationTitle(
            session.draft.taskID == nil
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
                    clearInputFocus()
                    session.requestCancel(whenClean: onCancel)
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isInteractionDisabled)
                .accessibilityIdentifier("task.editor.cancel")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(AppStrings.localized("common.save")) {
                    clearInputFocus()
                    session.save(
                        using: onSave,
                        onSaved: { _ in onSaved() }
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    isInteractionDisabled ||
                        !session.isPersistenceValid
                )
                .accessibilityIdentifier("task.editor.save")
            }

            #if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AppStrings.done) {
                    clearInputFocus()
                }
                .accessibilityIdentifier("task.editor.keyboard.done")
            }
            #endif
        }
        .taskEditorSessionSafety(
            session: session,
            discard: onCancel,
            reload: {
                session.reloadLatestDraft()
                clearInputFocus()
            }
        )
    }

    private func clearInputFocus() {
        focusedTextField = nil
        focusedChecklistDraftID = nil
    }
}
