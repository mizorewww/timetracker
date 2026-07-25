import Foundation
import SwiftData

extension StoreScopedTaskRecurrenceCommandCoordinator {
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
              false
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

private extension StoreScopedTaskRecurrenceCommandCoordinator {
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
