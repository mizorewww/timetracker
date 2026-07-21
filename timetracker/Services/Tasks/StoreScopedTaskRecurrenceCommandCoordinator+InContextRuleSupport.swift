import Foundation
import SwiftData

extension StoreScopedTaskRecurrenceCommandCoordinator {
    func insertDailyRule(
        templateTaskID: UUID,
        startDayKey: String,
        timeZoneIdentifier: String,
        isEnabled: Bool,
        now: Date,
        context: ModelContext,
        state: inout TaskRecurrencePersistenceState,
        outcome: inout TaskRecurrenceMutationOutcome
    ) throws -> TaskRecurrenceRule {
        let ruleID = TaskProgressIdentity.recurrenceRuleID(
            templateTaskID: templateTaskID
        )
        guard state.activeWorkTaskIDs.contains(templateTaskID) == false else {
            throw TaskRecurrenceMutationError.templateHasActiveWork
        }
        guard state.claimedRuleIDs.contains(ruleID) == false,
              state.claimedRuleTemplateTaskIDs.contains(
                templateTaskID
              ) == false else {
            throw TaskRecurrenceMutationError.ruleUnavailable
        }
        let rule = TaskRecurrenceRule(
            templateTaskID: templateTaskID,
            startDayKey: startDayKey,
            timeZoneIdentifier: timeZoneIdentifier,
            deviceID: deviceID
        )
        rule.isEnabled = isEnabled
        rule.createdAt = now
        rule.updatedAt = now
        rule.clientMutationID = UUID()
        context.insert(rule)
        state.rulesByID[rule.id] = rule
        outcome.markRuleChanged(
            templateTaskID: templateTaskID,
            affectedAncestorTaskIDs: state.ancestors(of: templateTaskID)
        )
        try didReachCheckpoint(.ruleCreated(rule.id))
        return rule
    }

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
