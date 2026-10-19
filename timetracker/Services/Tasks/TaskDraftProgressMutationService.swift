import Foundation
import SwiftData

nonisolated struct TaskDraftProgressMutationService {
    let context: ModelContext
    let session: StoreMutationSession
    let deviceID: String

    func apply(
        _ draft: PreparedTaskProgressDraft,
        to taskID: UUID,
        now: Date
    ) throws -> TaskRecurrenceMutationOutcome {
        try saveQuantityGoal(
            draft.quantityGoal,
            confirmsProgressReset:
            draft.confirmsQuantityProgressReset,
            taskID: taskID,
            now: now
        )
        return try saveDailyRecurrence(
            draft.dailyRecurrence,
            taskID: taskID,
            now: now
        )
    }

    private func saveDailyRecurrence(
        _ draft: TaskDailyRecurrenceDraft?,
        taskID: UUID,
        now: Date
    ) throws -> TaskRecurrenceMutationOutcome {
        var state = try TaskRecurrencePersistenceState(context: context)
        let ruleID = TaskProgressIdentity.recurrenceRuleID(
            templateTaskID: taskID
        )
        let existing = state.rulesByID[ruleID]
        guard let draft else {
            guard let existing, existing.deletedAt == nil else {
                return .noChanges
            }
            throw TaskProgressDraftMutationError
                .existingRecurrenceMustBePreserved
        }

        let coordinator = StoreScopedTaskRecurrenceCommandCoordinator(
            session: session,
            deviceID: deviceID
        )
        if let existing, existing.deletedAt == nil {
            guard existing.startDayKey == draft.startDayKey,
                  existing.timeZoneIdentifier == draft.timeZoneIdentifier
            else {
                throw TaskRecurrenceMutationError
                    .immutableRuleConfiguration
            }
            return try coordinator.setEnabled(
                baseline: TaskRecurrenceRuleMutationBaseline(
                    rule: existing
                ),
                isEnabled: draft.isEnabled,
                now: now,
                context: context,
                state: &state
            )
        }
        return try coordinator.createDailyRule(
            templateTaskID: taskID,
            startDayKey: draft.startDayKey,
            timeZoneIdentifier: draft.timeZoneIdentifier,
            isEnabled: draft.isEnabled,
            now: now,
            context: context,
            state: &state
        )
    }
}
