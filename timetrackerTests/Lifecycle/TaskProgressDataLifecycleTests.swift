import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskProgressDataLifecycleTests {
    @Test @MainActor
    func clearAllTombstonesTaskProgressAfterFutureDatedRows() throws {
        let context = try makeTestContext()
        let records = makeProgressGraph()
        let future = Date().addingTimeInterval(365 * 24 * 60 * 60)
        for model in records.softDeletableModels {
            model.updatedAt = future
        }
        insert(records, into: context)
        try context.save()

        try SeedData.clearAllChanges(
            context: context,
            includesPreferences: false
        )

        for model in records.softDeletableModels {
            let deletedAt = try #require(model.deletedAt)
            #expect(model.updatedAt == deletedAt)
            #expect(deletedAt > future)
        }
        let snapshot = try SyncDataSnapshot.capture(context: context)
        #expect(snapshot.taskRecurrenceRules?.count == 1)
        #expect(snapshot.taskRecurrenceOccurrences?.count == 1)
        #expect(snapshot.taskQuantityGoals?.count == 1)
        #expect(snapshot.taskQuantityEntries?.count == 1)
        #expect(snapshot.hasProtectableUserContent)
        #expect(snapshot.hasVisibleUserContent == false)
    }

    @Test @MainActor
    func taskStoreFullAndScopedRefreshConvergeTaskProgress() throws {
        let context = try makeTestContext()
        let records = makeProgressGraph()
        insert(records, into: context)
        try context.save()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        var store = TaskStore()

        try store.refresh(repository: repository)

        #expect(store.recurrenceRules.map(\.id) == [records.rule.id])
        #expect(
            store.recurrenceOccurrences.map(\.id) ==
                [records.occurrence.id]
        )
        #expect(store.quantityGoals.map(\.id) == [records.goal.id])
        #expect(store.quantityEntries.map(\.id) == [records.entry.id])

        let deletedAt = Date()
        for model in records.softDeletableModels {
            model.deletedAt = deletedAt
            model.updatedAt = deletedAt
        }
        try context.save()
        try store.refreshTaskScoped(
            taskIDs: [records.template.id],
            repository: repository
        )

        #expect(store.recurrenceRules.isEmpty)
        #expect(store.recurrenceOccurrences.isEmpty)
        #expect(store.quantityGoals.isEmpty)
        #expect(store.quantityEntries.isEmpty)
    }

    @Test @MainActor
    func templateScopedRefreshIncludesGeneratedQuantityDataAcrossContexts() throws {
        let context = try makeTestContext()
        let records = makeProgressGraph()
        context.insert(records.template)
        context.insert(records.rule)
        try context.save()

        var store = TaskStore()
        try store.refresh(
            repository: SwiftDataTaskRepository(
                context: context,
                deviceID: "initial"
            )
        )
        #expect(store.tasks.map(\.id) == [records.template.id])

        let siblingContext = ModelContext(context.container)
        siblingContext.insert(records.generatedTask)
        siblingContext.insert(records.occurrence)
        siblingContext.insert(records.goal)
        siblingContext.insert(records.entry)
        try siblingContext.save()

        try store.refreshTaskScoped(
            taskIDs: [records.template.id],
            repository: SwiftDataTaskRepository(
                context: ModelContext(context.container),
                deviceID: "reader"
            )
        )
        #expect(Set(store.tasks.map(\.id)) == [
            records.template.id,
            records.generatedTask.id,
        ])
        #expect(store.recurrenceOccurrences.map(\.id) == [
            records.occurrence.id,
        ])
        #expect(store.quantityGoals.map(\.id) == [records.goal.id])
        #expect(store.quantityEntries.map(\.id) == [records.entry.id])

        let deletedAt = Date()
        let quantityModels: [any SoftDeletablePersistentUUIDModel] = [
            records.goal,
            records.entry,
        ]
        for model in quantityModels {
            model.deletedAt = deletedAt
            model.updatedAt = deletedAt
        }
        try siblingContext.save()

        try store.refreshTaskScoped(
            taskIDs: [records.template.id],
            repository: SwiftDataTaskRepository(
                context: ModelContext(context.container),
                deviceID: "reader"
            )
        )
        #expect(store.quantityGoals.isEmpty)
        #expect(store.quantityEntries.isEmpty)
    }

    @Test @MainActor
    func maintenancePurgesExpiredMetadataButKeepsGeneratedTask() throws {
        let context = try makeTestContext()
        let records = makeProgressGraph()
        let now = Date(timeIntervalSinceReferenceDate: 20_000_000)
        let expiredAt = now.addingTimeInterval(
            -DatabaseMaintenanceService.defaultTombstoneRetention - 1
        )
        records.template.deletedAt = expiredAt
        records.template.updatedAt = expiredAt
        insert(records, into: context)
        try context.save()

        let count = try DatabaseMaintenanceService().optimizeDatabase(
            context: context,
            now: now,
            allowsPermanentTombstonePurge: true
        )

        #expect(count == 3)
        #expect(
            try context.fetch(FetchDescriptor<TaskNode>()).map(\.id) ==
                [records.generatedTask.id]
        )
        #expect(try context.fetch(FetchDescriptor<TaskRecurrenceRule>()).isEmpty)
        #expect(
            try context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                .isEmpty
        )
        #expect(
            try context.fetch(FetchDescriptor<TaskQuantityGoal>()).map(\.id) ==
                [records.goal.id]
        )
        #expect(
            try context.fetch(FetchDescriptor<TaskQuantityEntry>()).map(\.id) ==
                [records.entry.id]
        )
    }

    @Test @MainActor
    func maintenancePreservesVisibleProgressOrphansDuringImport() throws {
        let context = try makeTestContext()
        let records = makeProgressGraph()
        context.insert(records.rule)
        context.insert(records.occurrence)
        context.insert(records.goal)
        context.insert(records.entry)
        try context.save()

        let count = try DatabaseMaintenanceService().optimizeDatabase(
            context: context,
            allowsPermanentTombstonePurge: true
        )

        #expect(count == 0)
        #expect(try context.fetch(FetchDescriptor<TaskRecurrenceRule>()).count == 1)
        #expect(
            try context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
                .count == 1
        )
        #expect(try context.fetch(FetchDescriptor<TaskQuantityGoal>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TaskQuantityEntry>()).count == 1)

        var store = TaskStore()
        try store.refresh(
            repository: SwiftDataTaskRepository(
                context: context,
                deviceID: "test"
            )
        )
        #expect(store.recurrenceRules.isEmpty)
        #expect(store.recurrenceOccurrences.isEmpty)
        #expect(store.quantityGoals.isEmpty)
        #expect(store.quantityEntries.isEmpty)
    }

    @Test @MainActor
    func taskStoreHidesSemanticallyMismatchedImportedRelationships() throws {
        let context = try makeTestContext()
        let records = makeProgressGraph()
        let unrelated = TaskNode(
            title: "Unrelated",
            parentID: nil,
            deviceID: "test"
        )
        records.occurrence.templateTaskID = unrelated.id
        records.entry.taskID = records.template.id
        insert(records, into: context)
        context.insert(unrelated)
        try context.save()

        var store = TaskStore()
        try store.refresh(
            repository: SwiftDataTaskRepository(
                context: context,
                deviceID: "test"
            )
        )

        #expect(store.recurrenceRules.map(\.id) == [records.rule.id])
        #expect(store.recurrenceOccurrences.isEmpty)
        #expect(store.quantityGoals.map(\.id) == [records.goal.id])
        #expect(store.quantityEntries.isEmpty)
    }

    @MainActor
    private func makeProgressGraph() -> ProgressGraph {
        let template = TaskNode(
            title: "Daily push-ups",
            parentID: nil,
            deviceID: "test"
        )
        let rule = TaskRecurrenceRule(
            templateTaskID: template.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "Asia/Singapore",
            deviceID: "test"
        )
        let occurrence = TaskRecurrenceOccurrence(
            ruleID: rule.id,
            templateTaskID: template.id,
            occurrenceDayKey: "2026-07-20",
            timeZoneIdentifier: rule.timeZoneIdentifier,
            deviceID: "test"
        )
        let generatedTask = TaskNode(
            title: "50 push-ups",
            parentID: template.id,
            deviceID: "test"
        )
        generatedTask.id = occurrence.generatedTaskID
        let goal = TaskQuantityGoal(
            taskID: generatedTask.id,
            targetAmount: 50,
            unitLabel: "push-ups",
            deviceID: "test"
        )
        let entry = TaskQuantityEntry(
            id: UUID(),
            taskID: generatedTask.id,
            amount: 20,
            deviceID: "test"
        )
        return ProgressGraph(
            template: template,
            generatedTask: generatedTask,
            rule: rule,
            occurrence: occurrence,
            goal: goal,
            entry: entry
        )
    }

    @MainActor
    private func insert(
        _ records: ProgressGraph,
        into context: ModelContext
    ) {
        context.insert(records.template)
        context.insert(records.generatedTask)
        context.insert(records.rule)
        context.insert(records.occurrence)
        context.insert(records.goal)
        context.insert(records.entry)
    }
}

@MainActor
private struct ProgressGraph {
    let template: TaskNode
    let generatedTask: TaskNode
    let rule: TaskRecurrenceRule
    let occurrence: TaskRecurrenceOccurrence
    let goal: TaskQuantityGoal
    let entry: TaskQuantityEntry

    var softDeletableModels: [any SoftDeletablePersistentUUIDModel] {
        [rule, occurrence, goal, entry]
    }
}
