import Foundation
import Testing

@Suite(.serialized)
struct TaskProgressEditorUIContractTests {
    @Test
    func sharedEditorUsesNativeQuantityAndDailyControls() throws {
        let components = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorComponents.swift"
        )
        let quantity = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskQuantityEditorSection.swift"
        )
        let recurrence = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskRecurrenceEditorSection.swift"
        )

        #expect(components.contains("TaskQuantityEditorSection("))
        #expect(components.contains("TaskRecurrenceEditorSection("))
        #expect(quantity.contains("Toggle("))
        #expect(quantity.contains("TextField("))
        #expect(quantity.contains("LabeledContent"))
        #expect(quantity.contains(".keyboardType(.numberPad)"))
        #expect(quantity.contains("equals: .quantityTarget"))
        #expect(quantity.contains("equals: .quantityUnit"))
        #expect(quantity.contains(".confirmationDialog("))
        #expect(quantity.contains("role: .destructive"))
        #expect(quantity.contains("task.editor.quantity.remove.confirm"))
        #expect(quantity.contains("task.editor.quantity.toggle"))
        #expect(quantity.contains("task.editor.quantity.target"))
        #expect(quantity.contains("task.editor.quantity.unit"))
        #expect(quantity.contains("task.editor.quantity.error"))
        #expect(recurrence.contains("Toggle("))
        #expect(recurrence.contains("LabeledContent("))
        #expect(recurrence.contains("updated.setDailyRecurrenceEnabled(isEnabled)"))
        #expect(recurrence.contains("task.editor.recurrence.daily"))
        #expect(recurrence.contains("task.editor.recurrence.generated"))
        #expect(components.contains("store.isGeneratedRecurrenceTask"))
        #expect(components.contains("store.taskHasActiveWork"))
    }

    @Test
    func quantityRemovalRequiresOneShotDraftAuthority() throws {
        let quantity = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskQuantityEditorSection.swift"
        )
        let mutation = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorSession+Progress.swift"
        )

        #expect(quantity.contains("draft.baseline?.quantityGoalMutationID != nil"))
        #expect(quantity.contains("isRemovalConfirmationPresented = true"))
        #expect(quantity.contains("confirmQuantityGoalRemoval()"))
        #expect(quantity.contains("draft.requiresQuantityGoalRemovalConfirmation"))
        #expect(mutation.contains("confirmsQuantityProgressReset = true"))
        #expect(mutation.contains("confirmsQuantityProgressReset = false"))
        #expect(mutation.contains("baseline?.quantityGoalMutationID != nil"))
    }
}
