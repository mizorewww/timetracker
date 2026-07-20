import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskProgressPreflightContractTests {
    @Test @MainActor
    func deterministicIdentitiesAreStableAndDomainSeparated() throws {
        let taskID = TaskProgressPersistenceTestIDs.templateTask
        let ruleID = TaskProgressIdentity.recurrenceRuleID(
            templateTaskID: taskID
        )
        let occurrenceID = TaskProgressIdentity.recurrenceOccurrenceID(
            ruleID: ruleID,
            dayKey: "2026-07-20"
        )
        let generatedTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: ruleID,
            dayKey: "2026-07-20"
        )
        let goalID = TaskProgressIdentity.quantityGoalID(taskID: taskID)

        #expect(
            ruleID ==
                UUID(uuidString: "72E6D294-1F83-885A-BD96-5C5FEAC12460")
        )
        #expect(
            occurrenceID ==
                UUID(uuidString: "6D96A03B-A440-85C1-80CE-4842B3DE34D9")
        )
        #expect(
            generatedTaskID ==
                UUID(uuidString: "BB844BCB-03B1-8F85-AF54-2D2CC380A4DF")
        )
        #expect(
            goalID ==
                UUID(uuidString: "84627C5B-33A6-8A7D-8B15-F4C953084541")
        )
        #expect(occurrenceID != generatedTaskID)
        #expect(
            TaskProgressIdentity.recurrenceOccurrenceID(
                ruleID: ruleID,
                dayKey: "2026-07-21"
            ) != occurrenceID
        )

        let fixture = makeTaskProgressPersistenceFixture()
        #expect(fixture.rule.id == ruleID)
        #expect(fixture.occurrence.id == occurrenceID)
        #expect(fixture.occurrence.generatedTaskID == generatedTaskID)
        #expect(fixture.goal.id == TaskProgressIdentity.quantityGoalID(
            taskID: fixture.generatedTask.id
        ))
        #expect(fixture.entry.quantityGoalID == fixture.goal.id)
    }

    @Test @MainActor
    func preflightRejectsNonCanonicalPersistentIdentity() {
        let fixture = makeTaskProgressPersistenceFixture()
        let expectedID = fixture.rule.id
        fixture.rule.id = UUID()
        let record = TaskRecurrenceRuleRecord(fixture.rule)

        #expect(throws: SyncDataSnapshotPreflightError.nonCanonicalIdentity(
            table: .taskRecurrenceRules,
            id: record.id,
            expectedID: expectedID
        )) {
            try SyncDataSnapshot(taskRecurrenceRules: [record])
                .validateForRestore()
        }
    }

    @Test @MainActor
    func preflightRejectsNonCanonicalDayKeys() {
        let rule = makeTaskProgressPersistenceFixture().rule
        rule.startDayKey = "2026-02-30"
        let record = TaskRecurrenceRuleRecord(rule)

        #expect(throws: SyncDataSnapshotPreflightError.invalidRawValue(
            table: .taskRecurrenceRules,
            id: record.id,
            field: "startDayKey",
            value: "2026-02-30"
        )) {
            try SyncDataSnapshot(taskRecurrenceRules: [record])
                .validateForRestore()
        }

        let occurrence = makeTaskProgressPersistenceFixture().occurrence
        occurrence.occurrenceDayKey = "2026-7-20"
        occurrence.id = TaskProgressIdentity.recurrenceOccurrenceID(
            ruleID: occurrence.ruleID,
            dayKey: occurrence.occurrenceDayKey
        )
        occurrence.generatedTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: occurrence.ruleID,
            dayKey: occurrence.occurrenceDayKey
        )
        let occurrenceRecord = TaskRecurrenceOccurrenceRecord(occurrence)
        #expect(throws: SyncDataSnapshotPreflightError.invalidRawValue(
            table: .taskRecurrenceOccurrences,
            id: occurrenceRecord.id,
            field: "occurrenceDayKey",
            value: "2026-7-20"
        )) {
            try SyncDataSnapshot(
                taskRecurrenceOccurrences: [occurrenceRecord]
            ).validateForRestore()
        }
    }

    @Test @MainActor
    func preflightRejectsUnknownTimeZone() {
        let rule = makeTaskProgressPersistenceFixture().rule
        rule.timeZoneIdentifier = "Mars/Olympus"
        let record = TaskRecurrenceRuleRecord(rule)

        #expect(throws: SyncDataSnapshotPreflightError.invalidRawValue(
            table: .taskRecurrenceRules,
            id: record.id,
            field: "timeZoneIdentifier",
            value: "Mars/Olympus"
        )) {
            try SyncDataSnapshot(taskRecurrenceRules: [record])
                .validateForRestore()
        }
    }

    @Test @MainActor
    func preflightRejectsUnknownCadenceAndInvalidUnit() {
        let rule = makeTaskProgressPersistenceFixture().rule
        rule.cadenceRaw = "weekdays"
        let ruleRecord = TaskRecurrenceRuleRecord(rule)
        #expect(throws: SyncDataSnapshotPreflightError.invalidRawValue(
            table: .taskRecurrenceRules,
            id: ruleRecord.id,
            field: "cadenceRaw",
            value: "weekdays"
        )) {
            try SyncDataSnapshot(taskRecurrenceRules: [ruleRecord])
                .validateForRestore()
        }

        let goal = makeTaskProgressPersistenceFixture().goal
        goal.unitLabel = " \n"
        let goalRecord = TaskQuantityGoalRecord(goal)
        #expect(throws: SyncDataSnapshotPreflightError.invalidRawValue(
            table: .taskQuantityGoals,
            id: goalRecord.id,
            field: "unitLabel",
            value: " \n"
        )) {
            try SyncDataSnapshot(taskQuantityGoals: [goalRecord])
                .validateForRestore()
        }
    }

    @Test @MainActor
    func preflightRejectsOutOfRangeGoalAndEntryAmounts() {
        let goal = makeTaskProgressPersistenceFixture().goal
        goal.targetAmount = 0
        let goalRecord = TaskQuantityGoalRecord(goal)
        #expect(throws: SyncDataSnapshotPreflightError.invalidInteger(
            table: .taskQuantityGoals,
            id: goalRecord.id,
            field: "targetAmount",
            value: 0,
            allowed: "1...1000000"
        )) {
            try SyncDataSnapshot(taskQuantityGoals: [goalRecord])
                .validateForRestore()
        }

        let entry = makeTaskProgressPersistenceFixture().entry
        entry.amount = TaskQuantityPolicy.valueRange.upperBound + 1
        let entryRecord = TaskQuantityEntryRecord(entry)
        #expect(throws: SyncDataSnapshotPreflightError.invalidInteger(
            table: .taskQuantityEntries,
            id: entryRecord.id,
            field: "amount",
            value: 1_000_001,
            allowed: "1...1000000"
        )) {
            try SyncDataSnapshot(taskQuantityEntries: [entryRecord])
                .validateForRestore()
        }
    }

    @Test @MainActor
    func preflightRejectsMismatchedDeterministicReferences() {
        let occurrence = makeTaskProgressPersistenceFixture().occurrence
        let expectedTaskID = occurrence.generatedTaskID
        occurrence.generatedTaskID = UUID()
        let occurrenceRecord = TaskRecurrenceOccurrenceRecord(occurrence)

        #expect(throws: SyncDataSnapshotPreflightError.mismatchedReference(
            table: .taskRecurrenceOccurrences,
            id: occurrenceRecord.id,
            field: "generatedTaskID",
            expectedID: expectedTaskID,
            actualID: occurrenceRecord.generatedTaskID
        )) {
            try SyncDataSnapshot(
                taskRecurrenceOccurrences: [occurrenceRecord]
            ).validateForRestore()
        }

        let entry = makeTaskProgressPersistenceFixture().entry
        let expectedGoalID = entry.quantityGoalID
        entry.quantityGoalID = UUID()
        let entryRecord = TaskQuantityEntryRecord(entry)
        #expect(throws: SyncDataSnapshotPreflightError.mismatchedReference(
            table: .taskQuantityEntries,
            id: entryRecord.id,
            field: "quantityGoalID",
            expectedID: expectedGoalID,
            actualID: entryRecord.quantityGoalID
        )) {
            try SyncDataSnapshot(taskQuantityEntries: [entryRecord])
                .validateForRestore()
        }
    }

    @Test @MainActor
    func preflightRejectsOccurrenceOutsideItsRuleBoundary() {
        let timeZoneFixture = makeTaskProgressPersistenceFixture()
        timeZoneFixture.occurrence.timeZoneIdentifier = "UTC"
        let timeZoneRecord = TaskRecurrenceOccurrenceRecord(
            timeZoneFixture.occurrence
        )
        #expect(throws: SyncDataSnapshotPreflightError
            .inconsistentStringValue(
                table: .taskRecurrenceOccurrences,
                id: timeZoneRecord.id,
                field: "timeZoneIdentifier",
                expected: "Asia/Singapore",
                actual: "UTC"
            )) {
            try SyncDataSnapshot(
                taskRecurrenceRules: [
                    TaskRecurrenceRuleRecord(timeZoneFixture.rule)
                ],
                taskRecurrenceOccurrences: [timeZoneRecord]
            ).validateForRestore()
        }

        let dayFixture = makeTaskProgressPersistenceFixture()
        dayFixture.occurrence.occurrenceDayKey = "2026-07-19"
        dayFixture.occurrence.id =
            TaskProgressIdentity.recurrenceOccurrenceID(
                ruleID: dayFixture.rule.id,
                dayKey: "2026-07-19"
            )
        dayFixture.occurrence.generatedTaskID =
            TaskProgressIdentity.generatedTaskID(
                ruleID: dayFixture.rule.id,
                dayKey: "2026-07-19"
            )
        let dayRecord = TaskRecurrenceOccurrenceRecord(
            dayFixture.occurrence
        )
        #expect(throws: SyncDataSnapshotPreflightError
            .inconsistentStringValue(
                table: .taskRecurrenceOccurrences,
                id: dayRecord.id,
                field: "occurrenceDayKey",
                expected: "on or after 2026-07-20",
                actual: "2026-07-19"
            )) {
            try SyncDataSnapshot(
                taskRecurrenceRules: [
                    TaskRecurrenceRuleRecord(dayFixture.rule)
                ],
                taskRecurrenceOccurrences: [dayRecord]
            ).validateForRestore()
        }
    }

    @Test @MainActor
    func preflightAllowsValidRecordsWhenReferencedTablesAreNotInSnapshot() throws {
        let fixture = makeTaskProgressPersistenceFixture()
        let snapshot = SyncDataSnapshot(
            taskRecurrenceOccurrences: [
                TaskRecurrenceOccurrenceRecord(fixture.occurrence)
            ],
            taskQuantityEntries: [TaskQuantityEntryRecord(fixture.entry)]
        )

        try snapshot.validateForRestore()
    }
}
