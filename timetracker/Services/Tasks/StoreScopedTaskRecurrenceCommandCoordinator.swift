import Foundation
import SwiftData

/// Serializes recurrence rule changes and current-day materialization with the
/// same store lock used by task and timer commands. Scene-owned SwiftData
/// models never cross this boundary.
nonisolated struct StoreScopedTaskRecurrenceCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String
    let didReachCheckpoint:
        @Sendable (TaskRecurrenceMutationCheckpoint) throws -> Void

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String = DeviceIdentity.current,
        didReachCheckpoint: @escaping
        @Sendable (TaskRecurrenceMutationCheckpoint) throws -> Void = { _ in }
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
        self.didReachCheckpoint = didReachCheckpoint
    }

    @MainActor
    func materializeCurrentDay(
        now: Date = Date()
    ) throws -> TaskRecurrenceMutationOutcome {
        try withFreshState { context, state in
            var outcome = TaskRecurrenceMutationOutcome.noChanges
            let rules = state.rulesByID.values.sorted {
                $0.id.uuidString < $1.id.uuidString
            }
            for rule in rules {
                guard rule.deletedAt == nil,
                      rule.isEnabled,
                      rule.id == TaskProgressIdentity.recurrenceRuleID(
                          templateTaskID: rule.templateTaskID
                      ),
                      rule.cadenceRaw ==
                      TaskRecurrenceCadence.daily.rawValue,
                      TaskRecurrenceDayKey.isCanonical(rule.startDayKey),
                      Self.validTimeZone(rule.timeZoneIdentifier) != nil,
                      state.templateEligibleTaskIDs.contains(
                          rule.templateTaskID
                      ),
                      let template = state.taskByID[rule.templateTaskID],
                      template.deletedAt == nil,
                      template.isArchivedForLifecycle == false
                else {
                    continue
                }
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
    }
}

nonisolated extension StoreScopedTaskRecurrenceCommandCoordinator {
    @MainActor
    func withFreshState<Result>(
        _ operation: (
            ModelContext,
            inout TaskRecurrencePersistenceState
        ) throws -> Result
    ) throws -> Result {
        try StoreScopedMutationSession(
            container: container,
            writeAuthorization: writeAuthorization
        ).withFreshMutationContext { context in
            var state = try TaskRecurrencePersistenceState(context: context)
            return try operation(context, &state)
        }
    }

    @MainActor
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

    @MainActor
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

    static func validate(
        startDayKey: String,
        timeZoneIdentifier: String
    ) throws {
        guard TaskRecurrenceDayKey.isCanonical(startDayKey) else {
            throw TaskRecurrenceMutationError.invalidStartDay
        }
        guard validTimeZone(timeZoneIdentifier) != nil else {
            throw TaskRecurrenceMutationError.invalidTimeZone
        }
    }

    static func validTimeZone(_ identifier: String) -> TimeZone? {
        guard identifier.isEmpty == false,
              identifier.utf8.count <=
              TaskRecurrencePolicy.maximumTimeZoneIdentifierByteCount
        else {
            return nil
        }
        return TimeZone(identifier: identifier)
    }
}

nonisolated extension StoreScopedTaskRecurrenceCommandCoordinator {
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

nonisolated extension StoreScopedTaskRecurrenceCommandCoordinator {
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
              ) == false
        else {
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
              rule.templateTaskID == baseline.templateTaskID
        else {
            throw TaskRecurrenceMutationError.ruleUnavailable
        }
        guard rule.clientMutationID == baseline.clientMutationID else {
            throw TaskRecurrenceMutationError.ruleChanged
        }
        guard rule.cadenceRaw == TaskRecurrenceCadence.daily.rawValue,
              TaskRecurrenceDayKey.isCanonical(rule.startDayKey),
              Self.validTimeZone(rule.timeZoneIdentifier) != nil
        else {
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
              template.isArchivedForLifecycle == false
        else {
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

nonisolated extension StoreScopedTaskRecurrenceCommandCoordinator {
    func materializeCurrentDay(
        rule: TaskRecurrenceRule,
        template: TaskNode,
        now: Date,
        context: ModelContext,
        state: TaskRecurrencePersistenceState,
        outcome: inout TaskRecurrenceMutationOutcome
    ) throws {
        guard rule.isEnabled,
              let timeZone = TimeZone(
                  identifier: rule.timeZoneIdentifier
              )
        else {
            return
        }
        let dayKey = TaskRecurrenceDayKey.value(
            for: now,
            timeZone: timeZone
        )
        guard dayKey >= rule.startDayKey else { return }

        let occurrenceID = TaskProgressIdentity.recurrenceOccurrenceID(
            ruleID: rule.id,
            dayKey: dayKey
        )
        let generatedTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: rule.id,
            dayKey: dayKey
        )
        let generatedGoalID = TaskProgressIdentity.quantityGoalID(
            taskID: generatedTaskID
        )
        let occurrenceKey =
            TaskRecurrencePersistenceState.occurrenceKey(
                ruleID: rule.id,
                dayKey: dayKey
            )

        // Any physical claim can be a tombstone or one half of a staged
        // CloudKit import. Ordinary background work must wait instead of
        // manufacturing a newer active duplicate.
        guard state.claimedOccurrenceIDs.contains(occurrenceID) == false,
              state.claimedOccurrenceKeys.contains(occurrenceKey) == false,
              state.claimedTaskIDs.contains(generatedTaskID) == false,
              state.claimedQuantityGoalIDs.contains(generatedGoalID) ==
              false,
              try TaskRecurrencePersistenceState.hasQuantityEntryClaim(
                  taskID: generatedTaskID,
                  quantityGoalID: generatedGoalID,
                  in: context
              ) == false
        else {
            return
        }

        let blueprintGoal = quantityBlueprint(
            for: template.id,
            state: state
        )
        guard blueprintGoal.isValid else { return }

        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: deviceID
        )
        _ = try repository.createGeneratedRecurrenceTask(
            id: generatedTaskID,
            template: template,
            occurrenceDayKey: dayKey,
            now: now
        )
        try didReachCheckpoint(.generatedTaskCreated(generatedTaskID))

        var copiedGoalID: UUID?
        if let templateGoal = blueprintGoal.goal {
            let goal = TaskQuantityGoal(
                taskID: generatedTaskID,
                targetAmount: templateGoal.targetAmount,
                unitLabel: templateGoal.unitLabel,
                deviceID: deviceID
            )
            goal.createdAt = now
            goal.updatedAt = now
            goal.clientMutationID = goal.id
            context.insert(goal)
            copiedGoalID = goal.id
            try didReachCheckpoint(.quantityGoalCreated(goal.id))
        }

        let occurrence = TaskRecurrenceOccurrence(
            ruleID: rule.id,
            templateTaskID: template.id,
            occurrenceDayKey: dayKey,
            timeZoneIdentifier: rule.timeZoneIdentifier,
            deviceID: deviceID
        )
        occurrence.createdAt = now
        occurrence.updatedAt = now
        occurrence.clientMutationID = occurrence.id
        context.insert(occurrence)
        try didReachCheckpoint(.occurrenceCreated(occurrence.id))

        outcome.materializations.append(
            TaskRecurrenceMaterializationMutation(
                ruleID: rule.id,
                templateTaskID: template.id,
                occurrenceID: occurrence.id,
                generatedTaskID: generatedTaskID,
                generatedQuantityGoalID: copiedGoalID,
                affectedAncestorTaskIDs:
                state.ancestors(of: template.id)
                    .union([template.id])
            )
        )
    }
}

private nonisolated extension StoreScopedTaskRecurrenceCommandCoordinator {
    struct QuantityBlueprint {
        let goal: TaskQuantityGoal?
        let isValid: Bool
    }

    func quantityBlueprint(
        for templateTaskID: UUID,
        state: TaskRecurrencePersistenceState
    ) -> QuantityBlueprint {
        let goalID = TaskProgressIdentity.quantityGoalID(
            taskID: templateTaskID
        )
        guard let goal = state.quantityGoalByID[goalID] else {
            return QuantityBlueprint(goal: nil, isValid: true)
        }
        guard goal.deletedAt == nil else {
            return QuantityBlueprint(goal: nil, isValid: true)
        }
        let trimmedUnit = goal.unitLabel.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let hasControlCharacter = goal.unitLabel.unicodeScalars.contains(
            where: CharacterSet.controlCharacters.contains
        )
        let isValid = goal.taskID == templateTaskID &&
            TaskQuantityPolicy.valueRange.contains(goal.targetAmount) &&
            trimmedUnit.isEmpty == false &&
            hasControlCharacter == false &&
            goal.unitLabel.utf8.count <=
            TaskQuantityPolicy.maximumUnitLabelByteCount
        return QuantityBlueprint(
            goal: isValid ? goal : nil,
            isValid: isValid
        )
    }
}
