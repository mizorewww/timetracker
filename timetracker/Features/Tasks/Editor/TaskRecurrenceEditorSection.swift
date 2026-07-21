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
               draft.dailyRecurrence != nil {
                LabeledContent(
                    AppStrings.localized("task.recurrence.editor.frequency"),
                    value: AppStrings.localized(
                        "task.recurrence.editor.everyDay"
                    )
                )
            }

            if isGeneratedTask == false,
               isCreationBlockedByActiveWork,
               draft.dailyRecurrence != nil {
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
            Text(.app(footerKey))
        }
    }

    private var footerKey: String {
        if isGeneratedTask {
            return "task.recurrence.editor.generatedFooter"
        }
        if isCreationBlockedByActiveWork {
            return "task.recurrence.editor.activeWorkFooter"
        }
        return draft.dailyRecurrence?.isEnabled == false
            ? "task.recurrence.editor.pausedFooter"
            : "task.recurrence.editor.footer"
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
