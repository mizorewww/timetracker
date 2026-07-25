import Foundation

extension SyncDataSnapshot {
    func validateTaskProgressSemantics() throws {
        let rules = taskRecurrenceRules ?? []
        let ruleByID = Dictionary(
            uniqueKeysWithValues: rules.map { ($0.id, $0) }
        )

        for record in rules {
            let expectedID = TaskProgressIdentity.recurrenceRuleID(
                templateTaskID: record.templateTaskID
            )
            guard record.id == expectedID else {
                throw SyncDataSnapshotPreflightError.nonCanonicalIdentity(
                    table: .taskRecurrenceRules,
                    id: record.id,
                    expectedID: expectedID
                )
            }
            guard TaskRecurrenceCadence(rawValue: record.cadenceRaw) != nil else {
                throw invalidTaskProgressRawValue(
                    table: .taskRecurrenceRules,
                    id: record.id,
                    field: "cadenceRaw",
                    value: record.cadenceRaw
                )
            }
            try requireCanonicalDayKey(
                record.startDayKey,
                table: .taskRecurrenceRules,
                id: record.id,
                field: "startDayKey"
            )
            guard TimeZone(identifier: record.timeZoneIdentifier) != nil else {
                throw invalidTaskProgressRawValue(
                    table: .taskRecurrenceRules,
                    id: record.id,
                    field: "timeZoneIdentifier",
                    value: record.timeZoneIdentifier
                )
            }
            try requireMaximumBytes(
                record.timeZoneIdentifier,
                maximum:
                TaskRecurrencePolicy.maximumTimeZoneIdentifierByteCount,
                table: .taskRecurrenceRules,
                id: record.id,
                field: "timeZoneIdentifier"
            )
        }

        for record in taskRecurrenceOccurrences ?? [] {
            let expectedID = TaskProgressIdentity.recurrenceOccurrenceID(
                ruleID: record.ruleID,
                dayKey: record.occurrenceDayKey
            )
            guard record.id == expectedID else {
                throw SyncDataSnapshotPreflightError.nonCanonicalIdentity(
                    table: .taskRecurrenceOccurrences,
                    id: record.id,
                    expectedID: expectedID
                )
            }
            let expectedTaskID = TaskProgressIdentity.generatedTaskID(
                ruleID: record.ruleID,
                dayKey: record.occurrenceDayKey
            )
            guard record.generatedTaskID == expectedTaskID else {
                throw SyncDataSnapshotPreflightError.mismatchedReference(
                    table: .taskRecurrenceOccurrences,
                    id: record.id,
                    field: "generatedTaskID",
                    expectedID: expectedTaskID,
                    actualID: record.generatedTaskID
                )
            }
            try requireCanonicalDayKey(
                record.occurrenceDayKey,
                table: .taskRecurrenceOccurrences,
                id: record.id,
                field: "occurrenceDayKey"
            )
            guard TimeZone(identifier: record.timeZoneIdentifier) != nil else {
                throw invalidTaskProgressRawValue(
                    table: .taskRecurrenceOccurrences,
                    id: record.id,
                    field: "timeZoneIdentifier",
                    value: record.timeZoneIdentifier
                )
            }
            try requireMaximumBytes(
                record.timeZoneIdentifier,
                maximum:
                TaskRecurrencePolicy.maximumTimeZoneIdentifierByteCount,
                table: .taskRecurrenceOccurrences,
                id: record.id,
                field: "timeZoneIdentifier"
            )
            if let rule = ruleByID[record.ruleID] {
                guard record.templateTaskID == rule.templateTaskID else {
                    throw SyncDataSnapshotPreflightError.mismatchedReference(
                        table: .taskRecurrenceOccurrences,
                        id: record.id,
                        field: "templateTaskID",
                        expectedID: rule.templateTaskID,
                        actualID: record.templateTaskID
                    )
                }
                guard record.timeZoneIdentifier ==
                    rule.timeZoneIdentifier
                else {
                    throw SyncDataSnapshotPreflightError
                        .inconsistentStringValue(
                            table: .taskRecurrenceOccurrences,
                            id: record.id,
                            field: "timeZoneIdentifier",
                            expected: rule.timeZoneIdentifier,
                            actual: record.timeZoneIdentifier
                        )
                }
                guard record.occurrenceDayKey >= rule.startDayKey else {
                    throw SyncDataSnapshotPreflightError
                        .inconsistentStringValue(
                            table: .taskRecurrenceOccurrences,
                            id: record.id,
                            field: "occurrenceDayKey",
                            expected: "on or after \(rule.startDayKey)",
                            actual: record.occurrenceDayKey
                        )
                }
            }
        }

        for record in taskQuantityGoals ?? [] {
            let expectedID = TaskProgressIdentity.quantityGoalID(
                taskID: record.taskID
            )
            guard record.id == expectedID else {
                throw SyncDataSnapshotPreflightError.nonCanonicalIdentity(
                    table: .taskQuantityGoals,
                    id: record.id,
                    expectedID: expectedID
                )
            }
            try requireQuantityValue(
                record.targetAmount,
                table: .taskQuantityGoals,
                id: record.id,
                field: "targetAmount"
            )
            guard record.unitLabel.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty == false,
                record.unitLabel.unicodeScalars.contains(
                    where: CharacterSet.controlCharacters.contains
                ) == false
            else {
                throw invalidTaskProgressRawValue(
                    table: .taskQuantityGoals,
                    id: record.id,
                    field: "unitLabel",
                    value: record.unitLabel
                )
            }
            try requireMaximumBytes(
                record.unitLabel,
                maximum: TaskQuantityPolicy.maximumUnitLabelByteCount,
                table: .taskQuantityGoals,
                id: record.id,
                field: "unitLabel"
            )
        }

        let goalByID = Dictionary(
            uniqueKeysWithValues: (taskQuantityGoals ?? []).map {
                ($0.id, $0)
            }
        )
        for record in taskQuantityEntries ?? [] {
            let expectedGoalID = TaskProgressIdentity.quantityGoalID(
                taskID: record.taskID
            )
            guard record.quantityGoalID == expectedGoalID else {
                throw SyncDataSnapshotPreflightError.mismatchedReference(
                    table: .taskQuantityEntries,
                    id: record.id,
                    field: "quantityGoalID",
                    expectedID: expectedGoalID,
                    actualID: record.quantityGoalID
                )
            }
            try requireQuantityValue(
                record.amount,
                table: .taskQuantityEntries,
                id: record.id,
                field: "amount"
            )
            if let goal = goalByID[record.quantityGoalID],
               goal.taskID != record.taskID
            {
                throw SyncDataSnapshotPreflightError.mismatchedReference(
                    table: .taskQuantityEntries,
                    id: record.id,
                    field: "taskID",
                    expectedID: goal.taskID,
                    actualID: record.taskID
                )
            }
        }
    }
}
