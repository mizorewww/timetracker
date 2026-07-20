import SwiftUI

struct RecoveredTaskEditorSheet: View {
    let store: TimeTrackerStore
    let presentation: RecoveredTaskDraftPresentation
    @Environment(\.dismiss) private var dismiss
    @State private var savedTaskID: UUID?
    @State private var isFinishingCleanup = false
    @State private var isDiscardConfirmationPresented = false
    @State private var isDiscarding = false

    init(
        store: TimeTrackerStore,
        presentation: RecoveredTaskDraftPresentation
    ) {
        self.store = store
        self.presentation = presentation
        _savedTaskID = State(initialValue: presentation.savedTaskID)
    }

    var body: some View {
        NavigationStack {
            if savedTaskID == nil {
                TaskEditorPanel(
                    store: store,
                    initialDraft: presentation.draft,
                    isInteractionDisabled: isDiscarding,
                    onCancel: cancelEditing,
                    onSave: save,
                    onSaved: finishCleanup
                )
                .overlay {
                    if isDiscarding {
                        ProgressView(
                            AppStrings.localized(
                                "task.editor.recovery.discard"
                            )
                        )
                        .padding()
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .accessibilityIdentifier(
                            "task.editor.recovery.discarding"
                        )
                    }
                }
            } else {
                List {
                    TaskDraftRecoveryCleanupSection(
                        isRetrying: isFinishingCleanup,
                        retry: finishCleanup,
                        close: dismiss.callAsFunction
                    )
                }
                .navigationTitle(
                    AppStrings.localized("tasks.recovery.saved.title")
                )
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
            }
        }
        .platformSheetFrame(width: 520, height: 620)
        .presentationDetents([.large])
        .toolbar {
            if savedTaskID == nil {
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            isDiscardConfirmationPresented = true
                        } label: {
                            Label(
                                AppStrings.localized(
                                    "task.editor.recovery.discard"
                                ),
                                systemImage: "trash"
                            )
                        }
                    } label: {
                        Label(
                            AppStrings.localized("common.more"),
                            systemImage: "ellipsis.circle"
                        )
                    }
                    .disabled(isDiscarding)
                    .accessibilityIdentifier("task.editor.recovery.more")
                }
            }
        }
        .confirmationDialog(
            AppStrings.localized("tasks.recovery.discard.confirm.title"),
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                AppStrings.localized("task.editor.recovery.discard"),
                role: .destructive,
                action: discardRecovery
            )
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("tasks.recovery.discard.confirm.message"))
        }
    }

    private func save(_ draft: TaskEditorDraft) -> TaskDraftSaveResult {
        guard savedTaskID == nil, isDiscarding == false else {
            return .failed(
                message: AppStrings.localized(
                    "tasks.recovery.saved.cleanupMessage"
                )
            )
        }
        let result = store.saveRecoveredTaskDraftResult(
            draft,
            proposedTaskID: presentation.proposedTaskID,
            returnDestination: presentation.returnDestination
        )
        if case .saved(let taskID) = result {
            savedTaskID = taskID
        }
        return result
    }

    private func cancelEditing() {
        guard isDiscarding == false else { return }
        dismiss()
    }

    private func finishCleanup() {
        guard savedTaskID != nil, isFinishingCleanup == false else { return }
        isFinishingCleanup = true
        Task {
            defer { isFinishingCleanup = false }
            do {
                try await store.taskDraftRecoveryController
                    .removeInBackground(for: presentation.sourceTaskID)
                savedTaskID = nil
                dismiss()
            } catch {
                store.errorMessage = TaskDraftRecoveryErrorPresentation
                    .removalFailureMessage(for: error)
            }
        }
    }

    private func discardRecovery() {
        guard isDiscarding == false else { return }
        isDiscarding = true
        Task {
            defer { isDiscarding = false }
            do {
                try await store.taskDraftRecoveryController
                    .removeInBackground(for: presentation.sourceTaskID)
                dismiss()
            } catch {
                store.errorMessage = TaskDraftRecoveryErrorPresentation
                    .removalFailureMessage(for: error)
            }
        }
    }
}
