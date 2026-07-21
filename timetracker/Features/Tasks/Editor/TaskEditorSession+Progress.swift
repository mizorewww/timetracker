import Foundation

extension TaskEditorSession {
    func setQuantityGoal(
        _ quantityGoal: TaskQuantityGoalDraft?
    ) {
        draft.setQuantityGoal(quantityGoal)
    }

    func confirmQuantityGoalRemoval() {
        draft.confirmQuantityGoalRemoval()
    }

    func setDailyRecurrenceEnabled(
        _ isEnabled: Bool,
        now: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        draft.setDailyRecurrenceEnabled(
            isEnabled,
            now: now,
            timeZone: timeZone
        )
    }
}

extension TaskEditorDraft {
    var requiresQuantityGoalRemovalConfirmation: Bool {
        baseline?.quantityGoalMutationID != nil &&
            quantityGoal == nil &&
            confirmsQuantityProgressReset == false
    }

    mutating func setQuantityGoal(
        _ quantityGoal: TaskQuantityGoalDraft?
    ) {
        confirmsQuantityProgressReset = false
        self.quantityGoal = quantityGoal
    }

    mutating func confirmQuantityGoalRemoval() {
        guard baseline?.quantityGoalMutationID != nil else { return }
        quantityGoal = nil
        confirmsQuantityProgressReset = true
    }

    mutating func setDailyRecurrenceEnabled(
        _ isEnabled: Bool,
        now: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        if var recurrence = dailyRecurrence {
            if baseline?.recurrenceRuleMutationID != nil {
                recurrence.isEnabled = isEnabled
                dailyRecurrence = recurrence
            } else {
                dailyRecurrence = isEnabled ? recurrence : nil
            }
            return
        }
        guard isEnabled else { return }
        dailyRecurrence = TaskDailyRecurrenceDraft(
            startingAt: now,
            timeZone: timeZone
        )
    }
}
