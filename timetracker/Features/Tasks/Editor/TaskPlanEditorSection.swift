import SwiftUI

struct TaskPlanEditorSection: View {
    @Binding var draft: TaskEditorDraft

    var body: some View {
        Section {
            Stepper(value: estimatedMinutesBinding, in: TaskEstimatePolicy.minuteRange, step: 15) {
                LabeledContent(
                    AppStrings.localized("editor.task.estimate"),
                    value: estimatedMinutesLabel
                )
            }

            Toggle(
                AppStrings.localized("editor.task.setDue"),
                isOn: $draft.hasDueDate
            )
            .accessibilityIdentifier("task.editor.due.toggle")
            if draft.hasDueDate {
                DatePicker(
                    AppStrings.localized("editor.task.due"),
                    selection: $draft.dueAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
        } header: {
            Text(.app("editor.task.plan"))
        } footer: {
            Text(.app("editor.task.estimate.footer"))
        }
    }

    private var estimatedMinutesBinding: Binding<Int> {
        Binding {
            (draft.estimatedMinutes ?? 0).clamped(to: TaskEstimatePolicy.minuteRange)
        } set: { value in
            draft.estimatedMinutes = value == 0 ? nil : value
        }
    }

    private var estimatedMinutesLabel: String {
        draft.estimatedMinutes.map {
            String(format: AppStrings.localized("common.minutes"), $0)
        } ?? AppStrings.localized("editor.task.notSet")
    }
}
