import SwiftUI

struct TaskRecurrenceEditorSection: View {
    @Binding var draft: TaskEditorDraft
    let isGeneratedTask: Bool
    let isCreationBlockedByActiveWork: Bool

    var body: some View {
        Section {
            if isGeneratedTask {
                Label(
                    AppStrings.localized(
                        "task.recurrence.editor.generatedTask"
                    ),
                    systemImage: "calendar.badge.clock"
                )
                .accessibilityIdentifier(
                    "task.editor.recurrence.generated"
                )
            } else {
                Toggle(
                    AppStrings.localized("task.recurrence.editor.daily"),
                    isOn: dailyRecurrenceBinding
                )
                .disabled(
                    isCreationBlockedByActiveWork &&
                        draft.dailyRecurrence == nil
                )
                .accessibilityIdentifier("task.editor.recurrence.daily")
            }

            if isGeneratedTask == false,
               draft.dailyRecurrence != nil
            {
                LabeledContent(
                    AppStrings.localized("task.recurrence.editor.frequency"),
                    value: AppStrings.localized(
                        "task.recurrence.editor.everyDay"
                    )
                )
            }

            if isGeneratedTask == false,
               isCreationBlockedByActiveWork,
               draft.dailyRecurrence != nil
            {
                TaskEditorInlineErrorMessage(
                    message: TaskRecurrenceMutationError
                        .templateHasActiveWork.localizedDescription,
                    accessibilityIdentifier:
                    "task.editor.recurrence.activeWork.error"
                )
            }
        } header: {
            Text(.app("task.recurrence.editor.section"))
        } footer: {
            Text(footerText)
        }
    }

    private var footerText: String {
        switch TaskRecurrenceEditorFooterPolicy.state(
            isGeneratedTask: isGeneratedTask,
            isCreationBlockedByActiveWork:
            isCreationBlockedByActiveWork,
            dailyRecurrence: draft.dailyRecurrence,
            quantityGoal: draft.quantityGoal
        ) {
        case .generated:
            AppStrings.localized(
                "task.recurrence.editor.generatedFooter"
            )
        case .activeWorkBlocked:
            AppStrings.localized(
                "task.recurrence.editor.activeWorkFooter"
            )
        case .off:
            AppStrings.localized(
                "task.recurrence.editor.offFooter"
            )
        case .paused:
            AppStrings.localized(
                "task.recurrence.editor.pausedFooter"
            )
        case .enabled:
            AppStrings.localized("task.recurrence.editor.footer")
        case let .enabledWithQuantity(targetAmount, unitLabel):
            String.localizedStringWithFormat(
                AppStrings.localized(
                    "task.recurrence.editor.quantityFooterFormat"
                ),
                Int64(targetAmount),
                unitLabel
            )
        }
    }

    private var dailyRecurrenceBinding: Binding<Bool> {
        Binding {
            draft.dailyRecurrence?.isEnabled == true
        } set: { isEnabled in
            var updated = draft
            updated.setDailyRecurrenceEnabled(isEnabled)
            draft = updated
        }
    }
}

nonisolated enum TaskRecurrenceEditorFooterState: Equatable, Sendable {
    case generated
    case activeWorkBlocked
    case off
    case paused
    case enabled
    case enabledWithQuantity(targetAmount: Int, unitLabel: String)
}

nonisolated enum TaskRecurrenceEditorFooterPolicy {
    static func state(
        isGeneratedTask: Bool,
        isCreationBlockedByActiveWork: Bool,
        dailyRecurrence: TaskDailyRecurrenceDraft?,
        quantityGoal: TaskQuantityGoalDraft?
    ) -> TaskRecurrenceEditorFooterState {
        if isGeneratedTask {
            return .generated
        }
        if isCreationBlockedByActiveWork {
            return .activeWorkBlocked
        }
        guard let dailyRecurrence else { return .off }
        guard dailyRecurrence.isEnabled else { return .paused }
        guard let quantityGoal else { return .enabled }
        return .enabledWithQuantity(
            targetAmount: quantityGoal.targetAmount,
            unitLabel: quantityGoal.unitLabel
        )
    }
}
