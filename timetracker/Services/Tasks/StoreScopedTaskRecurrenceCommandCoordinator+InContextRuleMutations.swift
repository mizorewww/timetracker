import Foundation
import SwiftData

extension StoreScopedTaskRecurrenceCommandCoordinator {
    func createDailyRule(
        templateTaskID: UUID,
        startDayKey: String,
        timeZoneIdentifier: String,
        isEnabled: Bool = true,
        now: Date,
        context: ModelContext,
        state: inout TaskRecurrencePersistenceState
    ) throws -> TaskRecurrenceMutationOutcome {
        try Self.validate(
            startDayKey: startDayKey,
            timeZoneIdentifier: timeZoneIdentifier
        )
        guard state.templateEligibleTaskIDs.contains(templateTaskID),
              let template = state.taskByID[templateTaskID],
              template.deletedAt == nil,
              template.isArchivedForLifecycle == false
        else {
            throw TaskRecurrenceMutationError.templateUnavailable
        }

        let ruleID = TaskProgressIdentity.recurrenceRuleID(
            templateTaskID: templateTaskID
        )
        var outcome = TaskRecurrenceMutationOutcome.noChanges
        let rule: TaskRecurrenceRule
        if let existing = state.rulesByID[ruleID] {
            guard existing.deletedAt == nil else {
                throw TaskRecurrenceMutationError.ruleUnavailable
            }
            guard existing.templateTaskID == templateTaskID,
                  existing.cadenceRaw ==
                  TaskRecurrenceCadence.daily.rawValue,
                  existing.startDayKey == startDayKey,
                  existing.timeZoneIdentifier ==
                  timeZoneIdentifier
            else {
                throw TaskRecurrenceMutationError
                    .immutableRuleConfiguration
            }
            rule = existing
        } else {
            rule = try insertDailyRule(
                templateTaskID: templateTaskID,
                startDayKey: startDayKey,
                timeZoneIdentifier: timeZoneIdentifier,
                isEnabled: isEnabled,
                now: now,
                context: context,
                state: &state,
                outcome: &outcome
            )
        }

        if rule.isEnabled {
            try materializeCurrentDay(
                rule: rule,
                template: template,
                now: now,
                context: context,
                state: state,
                outcome: &outcome
            )
        }
        return outcome
    }

    func setEnabled(
        baseline: TaskRecurrenceRuleMutationBaseline,
        isEnabled: Bool,
        now: Date,
        context: ModelContext,
        state: inout TaskRecurrencePersistenceState
    ) throws -> TaskRecurrenceMutationOutcome {
        let rule = try requireRule(
            baseline: baseline,
            state: state
        )
        guard rule.isEnabled != isEnabled else {
            return try materializeEnabledRuleIfNeeded(
                rule,
                now: now,
                context: context,
                state: state
            )
        }

        rule.isEnabled = isEnabled
        rule.updatedAt = PersistentLWWMutationDate.strictlyDominating(
            preferred: now,
            observed: state.ruleRowsByID[rule.id, default: []]
                .map(\.updatedAt)
        )
        rule.deviceID = deviceID
        rule.clientMutationID = UUID()
        var outcome = TaskRecurrenceMutationOutcome.noChanges
        outcome.markRuleChanged(
            templateTaskID: rule.templateTaskID,
            affectedAncestorTaskIDs:
            state.ancestors(of: rule.templateTaskID)
        )
        try didReachCheckpoint(.ruleUpdated(rule.id))

        if isEnabled {
            let materialized = try materializeEnabledRuleIfNeeded(
                rule,
                now: now,
                context: context,
                state: state
            )
            outcome.materializations += materialized.materializations
        }
        return outcome
    }
}
