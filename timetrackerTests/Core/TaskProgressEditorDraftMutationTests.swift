import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskProgressEditorDraftMutationTests {
    @Test
    func quantityEditingKeepsDestructiveConfirmationExplicit() {
        var draft = TaskEditorDraft(parentID: nil)
        draft.baseline = baseline(quantityGoalMutationID: UUID())
        draft.setQuantityGoal(
            TaskQuantityGoalDraft(targetAmount: 50, unitLabel: "reps")
        )

        draft.setQuantityGoal(nil)
        #expect(draft.quantityGoal == nil)
        #expect(draft.confirmsQuantityProgressReset == false)

        draft.setQuantityGoal(
            TaskQuantityGoalDraft(targetAmount: 50, unitLabel: "reps")
        )
        draft.confirmQuantityGoalRemoval()
        #expect(draft.quantityGoal == nil)
        #expect(draft.confirmsQuantityProgressReset)

        draft.setQuantityGoal(TaskQuantityGoalDraft())
        #expect(draft.confirmsQuantityProgressReset == false)
    }

    @Test
    func recoveredQuantityRemovalRequiresFreshExplicitConfirmation()
        throws
    {
        var draft = TaskEditorDraft(parentID: nil)
        draft.baseline = baseline(quantityGoalMutationID: UUID())
        draft.setQuantityGoal(
            TaskQuantityGoalDraft(targetAmount: 50, unitLabel: "reps")
        )
        draft.confirmQuantityGoalRemoval()
        #expect(draft.confirmsQuantityProgressReset)

        let payload = try JSONEncoder().encode(draft)
        var recovered = try JSONDecoder().decode(
            TaskEditorDraft.self,
            from: payload
        )
        #expect(recovered.quantityGoal == nil)
        #expect(recovered.confirmsQuantityProgressReset == false)
        #expect(recovered.requiresQuantityGoalRemovalConfirmation)

        recovered.confirmQuantityGoalRemoval()
        #expect(recovered.confirmsQuantityProgressReset)
        #expect(recovered.requiresQuantityGoalRemovalConfirmation == false)
    }

    @Test
    func newQuantityGoalCannotGrantProgressResetAuthority() {
        var draft = TaskEditorDraft(parentID: nil)
        draft.setQuantityGoal(
            TaskQuantityGoalDraft(targetAmount: 50, unitLabel: "reps")
        )

        draft.confirmQuantityGoalRemoval()

        #expect(draft.quantityGoal != nil)
        #expect(draft.confirmsQuantityProgressReset == false)
    }

    @Test
    func newDailyRecurrenceUsesLocalTodayAndCanBeRemoved() throws {
        var draft = TaskEditorDraft(parentID: nil)
        let timeZone = try #require(
            TimeZone(identifier: "Asia/Singapore")
        )
        let now = Date(timeIntervalSince1970: 1_768_435_200)

        draft.setDailyRecurrenceEnabled(
            true,
            now: now,
            timeZone: timeZone
        )

        #expect(
            draft.dailyRecurrence?.startDayKey ==
                TaskRecurrenceDayKey.value(for: now, timeZone: timeZone)
        )
        #expect(draft.dailyRecurrence?.timeZoneIdentifier == timeZone.identifier)
        #expect(draft.dailyRecurrence?.isEnabled == true)

        draft.setDailyRecurrenceEnabled(false)
        #expect(draft.dailyRecurrence == nil)
    }

    @Test
    func existingDailyRecurrenceOnlyPausesAndResumes() {
        var draft = TaskEditorDraft(parentID: nil)
        draft.baseline = baseline(recurrenceRuleMutationID: UUID())
        draft.dailyRecurrence = TaskDailyRecurrenceDraft(
            isEnabled: true,
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )

        draft.setDailyRecurrenceEnabled(false)
        #expect(draft.dailyRecurrence?.isEnabled == false)
        #expect(draft.dailyRecurrence?.startDayKey == "2026-07-21")
        #expect(
            draft.dailyRecurrence?.timeZoneIdentifier == "Asia/Singapore"
        )

        draft.setDailyRecurrenceEnabled(true)
        #expect(draft.dailyRecurrence?.isEnabled == true)
        #expect(draft.dailyRecurrence?.startDayKey == "2026-07-21")
        #expect(
            draft.dailyRecurrence?.timeZoneIdentifier == "Asia/Singapore"
        )
    }

    @MainActor
    @Test
    func storeIdentifiesOnlyVisibleGeneratedRecurrenceTasks() throws {
        let context = try makeTestContext()
        let fixture = try insertTaskProgressPersistenceFixture(
            into: context
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(
            store.isGeneratedRecurrenceTask(
                taskID: fixture.generatedTask.id
            )
        )
        #expect(
            store.isGeneratedRecurrenceTask(
                taskID: fixture.templateTask.id
            ) == false
        )

        fixture.occurrence.deletedAt = Date(
            timeIntervalSinceReferenceDate: 200_000
        )
        fixture.occurrence.updatedAt = fixture.occurrence.deletedAt!
        fixture.occurrence.clientMutationID = UUID()
        try context.save()
        try store.refresh(plan: StoreRefreshPlan(scopes: [.tasks]))

        #expect(
            store.isGeneratedRecurrenceTask(
                taskID: fixture.generatedTask.id
            ) == false
        )
    }

    private func baseline(
        quantityGoalMutationID: UUID? = nil,
        recurrenceRuleMutationID: UUID? = nil
    ) -> TaskEditorDraftBaseline {
        TaskEditorDraftBaseline(
            taskMutationID: UUID(),
            checklistItemMutationIDs: [:],
            checklistVisualMutationIDs: [:],
            categoryAssignmentMutationID: nil,
            quantityGoalMutationID: quantityGoalMutationID,
            recurrenceRuleMutationID: recurrenceRuleMutationID
        )
    }
}
