import Foundation
import Testing
@testable import timetracker

struct TaskRecurrenceEditorFooterPolicyTests {
    @Test
    func footerStateCoversEveryRecurrenceEditorMode() {
        let enabled = TaskDailyRecurrenceDraft(
            isEnabled: true,
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )
        var paused = enabled
        paused.isEnabled = false

        #expect(state(isGenerated: true) == .generated)
        #expect(state(isBlocked: true) == .activeWorkBlocked)
        #expect(state() == .off)
        #expect(state(recurrence: paused) == .paused)
        #expect(state(recurrence: enabled) == .enabled)
        #expect(
            state(
                recurrence: enabled,
                quantity: TaskQuantityGoalDraft(
                    targetAmount: 50,
                    unitLabel: "reps"
                )
            ) == .enabledWithQuantity(
                targetAmount: 50,
                unitLabel: "reps"
            )
        )
    }

    private func state(
        isGenerated: Bool = false,
        isBlocked: Bool = false,
        recurrence: TaskDailyRecurrenceDraft? = nil,
        quantity: TaskQuantityGoalDraft? = nil
    ) -> TaskRecurrenceEditorFooterState {
        TaskRecurrenceEditorFooterPolicy.state(
            isGeneratedTask: isGenerated,
            isCreationBlockedByActiveWork: isBlocked,
            dailyRecurrence: recurrence,
            quantityGoal: quantity
        )
    }
}
