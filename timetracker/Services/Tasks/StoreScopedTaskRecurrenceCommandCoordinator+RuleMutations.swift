import Foundation

extension StoreScopedTaskRecurrenceCommandCoordinator {
    func createDailyRule(
        templateTaskID: UUID,
        startDayKey: String,
        timeZoneIdentifier: String,
        now: Date = Date()
    ) throws -> TaskRecurrenceMutationOutcome {
        try Self.validate(
            startDayKey: startDayKey,
            timeZoneIdentifier: timeZoneIdentifier
        )
        return try withFreshState { context, state in
            try createDailyRule(
                templateTaskID: templateTaskID,
                startDayKey: startDayKey,
                timeZoneIdentifier: timeZoneIdentifier,
                now: now,
                context: context,
                state: &state
            )
        }
    }
    func setEnabled(
        baseline: TaskRecurrenceRuleMutationBaseline,
        isEnabled: Bool,
        now: Date = Date()
    ) throws -> TaskRecurrenceMutationOutcome {
        try withFreshState { context, state in
            try setEnabled(
                baseline: baseline,
                isEnabled: isEnabled,
                now: now,
                context: context,
                state: &state
            )
        }
    }
}
