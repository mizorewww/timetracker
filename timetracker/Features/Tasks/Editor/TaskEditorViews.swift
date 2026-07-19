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
    @FocusState private var focusedChecklistDraftID: UUID?
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
            focusedChecklistDraftID: $focusedChecklistDraftID,
            orderedChecklistIndices: session.orderedChecklistIndices,
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
                    session.requestCancel(whenClean: onCancel)
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("task.editor.cancel")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(AppStrings.localized("common.save")) {
                    session.save(
                        using: onSave,
                        onSaved: onSaved
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!session.validation.isValid)
                .accessibilityIdentifier("task.editor.save")
            }
        }
        .taskEditorSessionSafety(
            session: session,
            discard: onCancel,
            reload: {
                session.reloadLatestDraft()
                focusedChecklistDraftID = nil
            }
        )
    }
}
