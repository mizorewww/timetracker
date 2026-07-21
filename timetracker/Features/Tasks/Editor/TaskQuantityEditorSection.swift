import SwiftUI

struct TaskQuantityEditorSection: View {
    let store: TimeTrackerStore
    @Binding var draft: TaskEditorDraft
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
    @State private var isRemovalConfirmationPresented = false

    var body: some View {
        Section {
            Toggle(
                AppStrings.localized("task.quantity.editor.toggle"),
                isOn: quantityEnabledBinding
            )
            .disabled(isReadModelIncomplete)
            .accessibilityIdentifier("task.editor.quantity.toggle")

            if draft.quantityGoal != nil {
                targetEditor
                unitEditor

                if let error = TaskProgressDraftPersistencePolicy
                    .quantityValidationError(for: draft.quantityGoal) {
                    TaskEditorInlineErrorMessage(
                        message: error.localizedDescription,
                        accessibilityIdentifier:
                            "task.editor.quantity.error"
                    )
                }
            }

            if isReadModelIncomplete {
                TaskEditorInlineErrorMessage(
                    message: TaskProgressDraftMutationError
                        .incompleteQuantityGraph.localizedDescription,
                    accessibilityIdentifier:
                        "task.editor.quantity.sync.error"
                )
            }
        } header: {
            Text(.app("task.quantity.editor.section"))
        } footer: {
            Text(.app(quantityFooterKey))
        }
        .confirmationDialog(
            AppStrings.localized("task.quantity.editor.remove.title"),
            isPresented: $isRemovalConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                AppStrings.localized("task.quantity.editor.remove.confirm"),
                role: .destructive
            ) {
                updateDraft { $0.confirmQuantityGoalRemoval() }
            }
            .accessibilityIdentifier("task.editor.quantity.remove.confirm")
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("task.quantity.editor.remove.message"))
        }
    }

    private var targetEditor: some View {
        LabeledContent {
            TextField(
                AppStrings.localized("task.quantity.editor.target"),
                value: targetAmountBinding,
                format: .number.grouping(.never)
            )
            .multilineTextAlignment(.trailing)
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .focused(focusedTextField, equals: .quantityTarget)
            .accessibilityIdentifier("task.editor.quantity.target")
        } label: {
            Text(.app("task.quantity.editor.target"))
        }
    }

    @ViewBuilder
    private var unitEditor: some View {
        LabeledContent {
            if isUnitLocked {
                Text(draft.quantityGoal?.unitLabel ?? "")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("task.editor.quantity.unit")
            } else {
                TextField(
                    AppStrings.localized("task.quantity.editor.unit"),
                    text: unitLabelBinding
                )
                .multilineTextAlignment(.trailing)
                .submitLabel(.done)
                .focused(focusedTextField, equals: .quantityUnit)
                .onSubmit {
                    focusedTextField.wrappedValue = nil
                }
                .accessibilityIdentifier("task.editor.quantity.unit")
            }
        } label: {
            Text(.app("task.quantity.editor.unit"))
        }
    }

    private var quantityEnabledBinding: Binding<Bool> {
        Binding {
            draft.quantityGoal != nil ||
                draft.requiresQuantityGoalRemovalConfirmation
        } set: { isEnabled in
            if isEnabled {
                guard draft.quantityGoal == nil else { return }
                updateDraft {
                    $0.setQuantityGoal(TaskQuantityGoalDraft())
                }
            } else if draft.baseline?.quantityGoalMutationID != nil {
                isRemovalConfirmationPresented = true
            } else {
                updateDraft { $0.setQuantityGoal(nil) }
            }
        }
    }

    private var quantityReadState: TaskQuantityProgressReadState {
        guard let taskID = draft.taskID else { return .none }
        return store.taskQuantityProgressReadState(
            for: taskID,
            expectedGoalMutationID:
                draft.baseline?.quantityGoalMutationID
        )
    }

    private var isReadModelIncomplete: Bool {
        if case .incomplete = quantityReadState { return true }
        return false
    }

    private var isUnitLocked: Bool {
        guard case .available(let progress) = quantityReadState else {
            return false
        }
        return progress.entryCount > 0
    }

    private var quantityFooterKey: String {
        isUnitLocked
            ? "task.quantity.editor.unitLockedFooter"
            : "task.quantity.editor.footer"
    }

    private var targetAmountBinding: Binding<Int> {
        Binding {
            draft.quantityGoal?.targetAmount ?? 1
        } set: { targetAmount in
            guard var goal = draft.quantityGoal else { return }
            goal.targetAmount = targetAmount
            updateDraft { $0.setQuantityGoal(goal) }
        }
    }

    private var unitLabelBinding: Binding<String> {
        Binding {
            draft.quantityGoal?.unitLabel ?? ""
        } set: { unitLabel in
            guard var goal = draft.quantityGoal else { return }
            goal.unitLabel = unitLabel
            updateDraft { $0.setQuantityGoal(goal) }
        }
    }

    private func updateDraft(
        _ mutation: (inout TaskEditorDraft) -> Void
    ) {
        var updated = draft
        mutation(&updated)
        draft = updated
    }
}
