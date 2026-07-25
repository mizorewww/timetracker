import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskProgressSnapshotContractTests {
    @Test @MainActor
    func taskDomainCaptureWritesAllProgressTablesIncludingEmptyArrays() throws {
        let populatedContext = try makeTestContext()
        let fixture = try insertTaskProgressPersistenceFixture(
            into: populatedContext
        )
        let full = try SyncDataSnapshot.capture(context: populatedContext)
        let incremental = try SyncDataSnapshot.capture(
            context: populatedContext,
            updating: SyncDataSnapshot(),
            domains: [.tasks]
        )

        for snapshot in [full, incremental] {
            #expect(snapshot.taskRecurrenceRules?.map(\.id) == [fixture.rule.id])
            #expect(
                snapshot.taskRecurrenceOccurrences?.map(\.id) ==
                    [fixture.occurrence.id]
            )
            #expect(snapshot.taskQuantityGoals?.map(\.id) == [fixture.goal.id])
            #expect(snapshot.taskQuantityEntries?.map(\.id) == [fixture.entry.id])
        }

        let empty = try SyncDataSnapshot.capture(context: makeTestContext())
        #expect(empty.taskRecurrenceRules == [])
        #expect(empty.taskRecurrenceOccurrences == [])
        #expect(empty.taskQuantityGoals == [])
        #expect(empty.taskQuantityEntries == [])
    }

    @Test @MainActor
    func legacyJSONMissingProgressKeysDecodesAsUnknownNotEmpty() throws {
        let captured = try SyncDataSnapshot.capture(context: makeTestContext())
        let encoded = try JSONEncoder().encode(captured)
        let explicit = try JSONDecoder().decode(
            SyncDataSnapshot.self,
            from: encoded
        )
        #expect(explicit.taskRecurrenceRules == [])
        #expect(explicit.taskRecurrenceOccurrences == [])
        #expect(explicit.taskQuantityGoals == [])
        #expect(explicit.taskQuantityEntries == [])

        var legacyJSON = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        for key in [
            "taskRecurrenceRules",
            "taskRecurrenceOccurrences",
            "taskQuantityGoals",
            "taskQuantityEntries",
        ] {
            legacyJSON.removeValue(forKey: key)
        }
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)
        let legacy = try JSONDecoder().decode(
            SyncDataSnapshot.self,
            from: legacyData
        )

        #expect(legacy.taskRecurrenceRules == nil)
        #expect(legacy.taskRecurrenceOccurrences == nil)
        #expect(legacy.taskQuantityGoals == nil)
        #expect(legacy.taskQuantityEntries == nil)
        #expect(legacy.inboxCaptureReceipts == [])
        #expect(legacy.localizedSummary != explicit.localizedSummary)
    }

    @Test @MainActor
    func optionalProgressMergeRequiresAKnownBaselineBeforeRemovingRows() {
        let fixture = makeTaskProgressPersistenceFixture()
        let records = progressSnapshot(for: fixture)

        var unknownMerge = records
        unknownMerge.applyChanges(
            from: SyncDataSnapshot(),
            to: authoritativeEmptyProgressSnapshot()
        )
        expectProgressRecordsRemain(unknownMerge, fixture: fixture)

        var noOpinionMerge = records
        noOpinionMerge.applyChanges(
            from: records,
            to: SyncDataSnapshot()
        )
        expectProgressRecordsRemain(noOpinionMerge, fixture: fixture)

        var knownMerge = records
        knownMerge.applyChanges(
            from: records,
            to: authoritativeEmptyProgressSnapshot()
        )
        #expect(knownMerge.taskRecurrenceRules == [])
        #expect(knownMerge.taskRecurrenceOccurrences == [])
        #expect(knownMerge.taskQuantityGoals == [])
        #expect(knownMerge.taskQuantityEntries == [])
    }

    @Test @MainActor
    func restoreTreatsNilAsNoOpinionAndExplicitEmptyAsDeletion() throws {
        let context = try makeTestContext()
        try insertTaskProgressPersistenceFixture(into: context)

        try SyncDataSnapshot().restoreAsLocalWinner(
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 200_000)
        )
        #expect(
            try context.fetch(FetchDescriptor<TaskRecurrenceRule>())
                .allSatisfy { $0.deletedAt == nil }
        )
        #expect(
            try context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                .allSatisfy { $0.deletedAt == nil }
        )
        #expect(
            try context.fetch(FetchDescriptor<TaskQuantityGoal>())
                .allSatisfy { $0.deletedAt == nil }
        )
        #expect(
            try context.fetch(FetchDescriptor<TaskQuantityEntry>())
                .allSatisfy { $0.deletedAt == nil }
        )

        try authoritativeEmptyProgressSnapshot().restoreAsLocalWinner(
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 300_000)
        )
        #expect(
            try context.fetch(FetchDescriptor<TaskRecurrenceRule>())
                .allSatisfy { $0.deletedAt != nil }
        )
        #expect(
            try context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                .allSatisfy { $0.deletedAt != nil }
        )
        #expect(
            try context.fetch(FetchDescriptor<TaskQuantityGoal>())
                .allSatisfy { $0.deletedAt != nil }
        )
        #expect(
            try context.fetch(FetchDescriptor<TaskQuantityEntry>())
                .allSatisfy { $0.deletedAt != nil }
        )
    }

    @Test @MainActor
    func fullSnapshotRoundTripRestoresProgressFieldsAndRelationships() throws {
        let source = try makeTestContext()
        let fixture = try insertTaskProgressPersistenceFixture(into: source)
        let encoded = try JSONEncoder().encode(
            SyncDataSnapshot.capture(context: source)
        )
        let snapshot = try JSONDecoder().decode(
            SyncDataSnapshot.self,
            from: encoded
        )

        let target = try makeTestContext()
        try snapshot.restoreAsLocalWinner(
            context: target,
            now: Date(timeIntervalSinceReferenceDate: 400_000)
        )

        let rule = try #require(
            try target.fetch(FetchDescriptor<TaskRecurrenceRule>()).first
        )
        let occurrence = try #require(
            try target.fetch(FetchDescriptor<TaskRecurrenceOccurrence>()).first
        )
        let goal = try #require(
            try target.fetch(FetchDescriptor<TaskQuantityGoal>()).first
        )
        let entry = try #require(
            try target.fetch(FetchDescriptor<TaskQuantityEntry>()).first
        )
        #expect(rule.id == fixture.rule.id)
        #expect(rule.templateTaskID == fixture.templateTask.id)
        #expect(rule.startDayKey == "2026-07-20")
        #expect(rule.timeZoneIdentifier == "Asia/Singapore")
        #expect(rule.isEnabled)
        #expect(occurrence.id == fixture.occurrence.id)
        #expect(occurrence.ruleID == rule.id)
        #expect(occurrence.templateTaskID == fixture.templateTask.id)
        #expect(occurrence.generatedTaskID == fixture.generatedTask.id)
        #expect(goal.id == fixture.goal.id)
        #expect(goal.taskID == occurrence.generatedTaskID)
        #expect(goal.targetAmount == 50)
        #expect(goal.unitLabel == "push-ups")
        #expect(entry.id == fixture.entry.id)
        #expect(entry.taskID == goal.taskID)
        #expect(entry.quantityGoalID == goal.id)
        #expect(entry.amount == 20)
        #expect(entry.recordedAt == fixture.entry.recordedAt)
        #expect([rule.deletedAt, occurrence.deletedAt, goal.deletedAt, entry.deletedAt]
            .allSatisfy { $0 == nil })
    }

    @Test @MainActor
    func stagedGeneratedTaskRestoreRemainsValidAfterHierarchyRepair() throws {
        let fixture = makeTaskProgressPersistenceFixture()
        let staged = SyncDataSnapshot(
            tasks: [TaskRecord(fixture.generatedTask)],
            taskRecurrenceOccurrences: [
                TaskRecurrenceOccurrenceRecord(fixture.occurrence),
            ]
        )
        let context = try makeTestContext()

        try staged.restoreAsLocalWinner(
            context: context,
            now: Date(timeIntervalSinceReferenceDate: 400_000)
        )
        let restoredTask = try #require(
            try context.fetch(FetchDescriptor<TaskNode>()).first
        )
        #expect(restoredTask.id == fixture.generatedTask.id)
        #expect(restoredTask.parentID == nil)

        let recaptured = try SyncDataSnapshot.capture(context: context)
        try recaptured.validateForRestore()
        #expect(
            recaptured.taskRecurrenceOccurrences?.first?.templateTaskID ==
                fixture.templateTask.id
        )
    }

    @Test @MainActor
    func progressTablesParticipateInFingerprintAndContentProtection() throws {
        let fixture = makeTaskProgressPersistenceFixture()
        let legacy = SyncDataSnapshot()
        let explicitEmpty = authoritativeEmptyProgressSnapshot()
        #expect(try legacy.fingerprint() != explicitEmpty.fingerprint())
        #expect(legacy.hasProtectableUserContent == false)
        #expect(explicitEmpty.hasProtectableUserContent == false)

        let activeSnapshots = [
            SyncDataSnapshot(
                taskRecurrenceRules: [TaskRecurrenceRuleRecord(fixture.rule)]
            ),
            SyncDataSnapshot(
                taskRecurrenceOccurrences: [
                    TaskRecurrenceOccurrenceRecord(fixture.occurrence),
                ]
            ),
            SyncDataSnapshot(
                taskQuantityGoals: [TaskQuantityGoalRecord(fixture.goal)]
            ),
            SyncDataSnapshot(
                taskQuantityEntries: [TaskQuantityEntryRecord(fixture.entry)]
            ),
        ]
        for snapshot in activeSnapshots {
            #expect(snapshot.hasProtectableUserContent)
            #expect(snapshot.hasVisibleUserContent)
            #expect(snapshot.localizedSummary != legacy.localizedSummary)
        }

        let deletionDate = Date(timeIntervalSinceReferenceDate: 200_000)
        fixture.rule.deletedAt = deletionDate
        fixture.occurrence.deletedAt = deletionDate
        fixture.goal.deletedAt = deletionDate
        fixture.entry.deletedAt = deletionDate
        let tombstones = progressSnapshot(for: fixture)
        #expect(tombstones.hasProtectableUserContent)
        #expect(tombstones.hasVisibleUserContent == false)
    }

    @MainActor
    private func progressSnapshot(
        for fixture: TaskProgressPersistenceFixture
    ) -> SyncDataSnapshot {
        SyncDataSnapshot(
            taskRecurrenceRules: [TaskRecurrenceRuleRecord(fixture.rule)],
            taskRecurrenceOccurrences: [
                TaskRecurrenceOccurrenceRecord(fixture.occurrence),
            ],
            taskQuantityGoals: [TaskQuantityGoalRecord(fixture.goal)],
            taskQuantityEntries: [TaskQuantityEntryRecord(fixture.entry)]
        )
    }

    private func authoritativeEmptyProgressSnapshot() -> SyncDataSnapshot {
        SyncDataSnapshot(
            taskRecurrenceRules: [],
            taskRecurrenceOccurrences: [],
            taskQuantityGoals: [],
            taskQuantityEntries: []
        )
    }

    @MainActor
    private func expectProgressRecordsRemain(
        _ snapshot: SyncDataSnapshot,
        fixture: TaskProgressPersistenceFixture
    ) {
        #expect(snapshot.taskRecurrenceRules?.map(\.id) == [fixture.rule.id])
        #expect(
            snapshot.taskRecurrenceOccurrences?.map(\.id) ==
                [fixture.occurrence.id]
        )
        #expect(snapshot.taskQuantityGoals?.map(\.id) == [fixture.goal.id])
        #expect(snapshot.taskQuantityEntries?.map(\.id) == [fixture.entry.id])
    }
}
