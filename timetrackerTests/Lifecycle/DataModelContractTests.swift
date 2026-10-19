import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct DataModelContractTests {
    @Test @MainActor
    func persistentDeduplicationUsesLastWriteWinsForTombstonesAndRestores() {
        let id = UUID()
        let base = Date(timeIntervalSinceReferenceDate: 100_000)
        let oldActive = TaskNode(title: "Old active", parentID: nil, deviceID: "test")
        oldActive.id = id
        oldActive.createdAt = base
        oldActive.updatedAt = base

        let newTombstone = TaskNode(title: "Deleted", parentID: nil, deviceID: "test")
        newTombstone.id = id
        newTombstone.createdAt = base
        newTombstone.updatedAt = base.addingTimeInterval(10)
        newTombstone.deletedAt = newTombstone.updatedAt

        let deletedWinner = [oldActive, newTombstone].deduplicatedByID()
        #expect(deletedWinner.count == 1)
        #expect(deletedWinner.first === newTombstone)

        let restored = TaskNode(title: "Restored", parentID: nil, deviceID: "test")
        restored.id = id
        restored.createdAt = base
        restored.updatedAt = base.addingTimeInterval(20)

        let restoredWinner = [newTombstone, restored].deduplicatedByID()
        #expect(restoredWinner.count == 1)
        #expect(restoredWinner.first === restored)
    }

    @Test @MainActor
    func persistentDeduplicationTieBreakIsStableAcrossFetchOrder() {
        let id = UUID()
        let timestamp = Date(timeIntervalSinceReferenceDate: 100_000)
        let first = TaskNode(title: "First", parentID: nil, deviceID: "device-a")
        first.id = id
        first.createdAt = timestamp
        first.updatedAt = timestamp
        let second = TaskNode(title: "Second", parentID: nil, deviceID: "device-b")
        second.id = id
        second.createdAt = timestamp
        second.updatedAt = timestamp

        #expect([first, second].deduplicatedByID().first === second)
        #expect([second, first].deduplicatedByID().first === second)
    }

    @Test @MainActor
    func modelDefaultsSupportCloudKitCompatibleConstruction() throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Defaults", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test")
        let segment = TimeSegment(sessionID: session.id, taskID: task.id, source: .timer, deviceID: "test")
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        let countdown = CountdownEvent(title: "Launch", date: Date(), deviceID: "test")
        let recurrenceRule = TaskRecurrenceRule(
            templateTaskID: task.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            deviceID: "test"
        )
        let recurrenceOccurrence = TaskRecurrenceOccurrence(
            ruleID: recurrenceRule.id,
            templateTaskID: task.id,
            occurrenceDayKey: "2026-07-20",
            timeZoneIdentifier: recurrenceRule.timeZoneIdentifier,
            deviceID: "test"
        )
        let quantityGoal = TaskQuantityGoal(
            taskID: task.id,
            targetAmount: 50,
            unitLabel: "push-ups",
            deviceID: "test"
        )
        let quantityEntry = TaskQuantityEntry(
            id: UUID(),
            taskID: task.id,
            amount: 10,
            deviceID: "test"
        )

        context.insert(task)
        context.insert(session)
        context.insert(segment)
        context.insert(run)
        context.insert(countdown)
        context.insert(recurrenceRule)
        context.insert(recurrenceOccurrence)
        context.insert(quantityGoal)
        context.insert(quantityEntry)
        try context.save()

        #expect(recurrenceRule.id == TaskProgressIdentity.recurrenceRuleID(templateTaskID: task.id))
        #expect(recurrenceOccurrence.generatedTaskID == TaskProgressIdentity.generatedTaskID(
            ruleID: recurrenceRule.id,
            dayKey: recurrenceOccurrence.occurrenceDayKey
        ))
        #expect(quantityGoal.id == TaskProgressIdentity.quantityGoalID(taskID: task.id))
        #expect(quantityEntry.quantityGoalID == quantityGoal.id)
    }

    @Test @MainActor
    func currentSchemaOpensWithTheMigrationPlanWithoutDerivedSummaries() throws {
        let schema = TimeTrackerModelRegistry.currentSchema
        #expect(TimeTrackerModelRegistry.cloudSyncedUserModelNames.contains("DailySummary") == false)
        #expect(schema.entity(for: DailySummary.self) == nil)
        let configuration = ModelConfiguration(
            "TimeTrackerCloudSyncContract",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        _ = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    @Test @MainActor
    func legacyTaskStatusRawValuesRemainPersistableButOnlyArchiveChangesLifecycle() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(title: "Plan draft", parentID: nil, colorHex: nil, iconName: nil)

        task.statusRaw = LegacyTaskStatusRaw.planned
        try context.save()
        #expect(try repository.task(id: task.id)?.statusRaw == LegacyTaskStatusRaw.planned)
        #expect(try repository.task(id: task.id)?.isArchivedForLifecycle == false)

        task.statusRaw = LegacyTaskStatusRaw.completed
        try context.save()
        #expect(try repository.task(id: task.id)?.statusRaw == LegacyTaskStatusRaw.completed)
        #expect(try repository.task(id: task.id)?.isArchivedForLifecycle == false)

        try repository.archiveTask(taskID: task.id)
        let archived = try #require(try repository.task(id: task.id))
        #expect(archived.statusRaw == LegacyTaskStatusRaw.archived)
        #expect(archived.archivedAt != nil)
        #expect(archived.isArchivedForLifecycle)
    }
}
