import Foundation
import SwiftData

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
            guard state.templateEligibleTaskIDs.contains(templateTaskID),
                  let template = state.taskByID[templateTaskID],
                  template.deletedAt == nil,
                  template.isArchivedForLifecycle == false else {
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
                        timeZoneIdentifier else {
                    throw TaskRecurrenceMutationError
                        .immutableRuleConfiguration
                }
                rule = existing
            } else {
                guard state.activeWorkTaskIDs.contains(templateTaskID) ==
                        false else {
                    throw TaskRecurrenceMutationError.templateHasActiveWork
                }
                guard state.claimedRuleIDs.contains(ruleID) == false,
                      state.claimedRuleTemplateTaskIDs.contains(
                        templateTaskID
                      ) == false else {
                    throw TaskRecurrenceMutationError.ruleUnavailable
                }
                let created = TaskRecurrenceRule(
                    templateTaskID: templateTaskID,
                    startDayKey: startDayKey,
                    timeZoneIdentifier: timeZoneIdentifier,
                    deviceID: deviceID
                )
                created.createdAt = now
                created.updatedAt = now
                created.clientMutationID = UUID()
                context.insert(created)
                state.rulesByID[created.id] = created
                outcome.markRuleChanged(
                    templateTaskID: templateTaskID,
                    affectedAncestorTaskIDs:
                        state.ancestors(of: templateTaskID)
                )
                try didReachCheckpoint(.ruleCreated(created.id))
                rule = created
            }

            try materializeCurrentDay(
                rule: rule,
                template: template,
                now: now,
                context: context,
                state: state,
                outcome: &outcome
            )
            return outcome
        }
    }
    func setEnabled(
        baseline: TaskRecurrenceRuleMutationBaseline,
        isEnabled: Bool,
        now: Date = Date()
    ) throws -> TaskRecurrenceMutationOutcome {
        try withFreshState { context, state in
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
}
private extension StoreScopedTaskRecurrenceCommandCoordinator {
    func requireRule(
        baseline: TaskRecurrenceRuleMutationBaseline,
        state: TaskRecurrencePersistenceState
    ) throws -> TaskRecurrenceRule {
        guard let rule = state.rulesByID[baseline.ruleID],
              rule.deletedAt == nil,
              rule.id == TaskProgressIdentity.recurrenceRuleID(
                templateTaskID: rule.templateTaskID
              ),
              rule.templateTaskID == baseline.templateTaskID else {
            throw TaskRecurrenceMutationError.ruleUnavailable
        }
        guard rule.clientMutationID == baseline.clientMutationID else {
            throw TaskRecurrenceMutationError.ruleChanged
        }
        guard rule.cadenceRaw == TaskRecurrenceCadence.daily.rawValue,
              TaskRecurrenceDayKey.isCanonical(rule.startDayKey),
              Self.validTimeZone(rule.timeZoneIdentifier) != nil else {
            throw TaskRecurrenceMutationError.immutableRuleConfiguration
        }
        return rule
    }
    func materializeEnabledRuleIfNeeded(
        _ rule: TaskRecurrenceRule,
        now: Date,
        context: ModelContext,
        state: TaskRecurrencePersistenceState
    ) throws -> TaskRecurrenceMutationOutcome {
        guard rule.isEnabled,
              state.templateEligibleTaskIDs.contains(rule.templateTaskID),
              let template = state.taskByID[rule.templateTaskID],
              template.deletedAt == nil,
              template.isArchivedForLifecycle == false else {
            return .noChanges
        }
        var outcome = TaskRecurrenceMutationOutcome.noChanges
        try materializeCurrentDay(
            rule: rule,
            template: template,
            now: now,
            context: context,
            state: state,
            outcome: &outcome
        )
        return outcome
    }
}
