import Foundation
import Testing

struct TaskQuantityDetailUIContractTests {
    @Test
    func detailUsesValidatedSnapshotsAndNativeProgressControls() throws {
        let content = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailContentView.swift"
        )
        let quantity = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailQuantityViews.swift"
        )
        let components = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailQuantityComponents.swift"
        )
        let readModels = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+TaskQuantityReadModels.swift"
        )
        let progressModels = try sourceText(
            "timetracker/Models/TaskQuantityProgressModels.swift"
        )

        #expect(content.contains("store.taskQuantityDetail(for: task.id)"))
        #expect(content.contains("taskQuantityEntries(for:") == false)
        #expect(quantity.contains("TaskQuantityDetailReadModel"))
        #expect(quantity.contains("ProgressView") == false)
        #expect(components.contains("ProgressView(value:"))
        #expect(quantity.contains("task.detail.quantity.record"))
        #expect(
            quantity.contains(
                ".accessibilityIdentifier(\"task.detail.quantity\")"
            ) == false
        )
        #expect(quantity.contains("task.detail.quantity.template"))
        #expect(quantity.contains("task.detail.quantity.occurrence"))
        #expect(quantity.contains("task.detail.quantity.entry."))
        #expect(quantity.contains("if detail.progress.isRecordingAllowed"))
        #expect(quantity.contains("showsNavigationChevron: false"))
        #expect(readModels.contains("validatedSnapshot("))
        #expect(readModels.contains("TaskRecurrenceOccurrenceSnapshot("))
        #expect(progressModels.contains("TaskRecurrenceDayKey.date("))
        #expect(
            readModels.contains(
                "taskIDsWithIncompleteRecurrence.contains(taskID)"
            )
        )
    }

    @Test
    func entryEditorCapturesBaselinesAndKeepsFailedSheetsOpen() throws {
        let models = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskQuantityEntryEditorModels.swift"
        )
        let views = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskQuantityEntryEditorViews.swift"
        )
        let actions = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskQuantityEntryEditorActions.swift"
        )

        #expect(models.contains("goalBaseline: TaskQuantityGoalMutationBaseline"))
        #expect(models.contains("entryID: UUID"))
        #expect(models.contains("updateOperationID: UUID"))
        #expect(models.contains("deleteOperationID: UUID"))
        #expect(views.contains("TextField("))
        #expect(views.contains("DatePicker("))
        #expect(views.contains(".confirmationDialog("))
        #expect(views.contains("task.detail.quantity.amount"))
        #expect(views.contains("ToolbarItemGroup(placement: .keyboard)"))
        #expect(views.contains("task.detail.quantity.keyboard.done"))
        #expect(views.contains("task.detail.quantity.delete.confirm"))
        #expect(views.contains("@State private var draft"))
        #expect(views.contains("@FocusState private var isAmountFocused"))
        #expect(actions.contains("goalBaseline: route.goalBaseline"))
        #expect(actions.contains("return store.recordTaskQuantity("))
        #expect(actions.contains("return store.deleteTaskQuantityEntry("))
        #expect(views.contains("TaskQuantityEntryEditorActions.save("))
    }

    @Test
    func detailFlushesDraftBeforeCapturingAQuantityRoute() throws {
        let content = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailContentView.swift"
        )
        let flush = try #require(
            content.range(of: "guard autosaveController.flush(")
        )
        let focus = try #require(
            content.range(
                of: "focusedTextField.wrappedValue = nil",
                range: flush.upperBound..<content.endIndex
            )
        )
        let reread = try #require(
            content.range(
                of: "switch store.taskQuantityDetail(for: task.id)",
                range: focus.upperBound..<content.endIndex
            )
        )

        #expect(flush.lowerBound < focus.lowerBound)
        #expect(focus.lowerBound < reread.lowerBound)
    }
}
