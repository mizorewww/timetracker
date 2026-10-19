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
    func cloudSyncedSchemaIncludesChecklistAndAllUserDataModels() throws {
        let requiredModelNames: Set = [
            "TaskNode",
            "TaskCategory",
            "TaskCategoryAssignment",
            "TimeSession",
            "TimeSegment",
            "PomodoroRun",
            "CountdownEvent",
            "SyncedPreference",
            "ChecklistItem",
            "ChecklistItemVisual",
            "InboxItem",
            "InboxSuggestion",
            "InboxCaptureReceipt",
            "TaskRecurrenceRule",
            "TaskRecurrenceOccurrence",
            "TaskQuantityGoal",
            "TaskQuantityEntry",
        ]

        #expect(requiredModelNames.isSubset(of: TimeTrackerModelRegistry.cloudSyncedUserModelNames))
        #expect(requiredModelNames.isSubset(of: Set(TimeTrackerModelRegistry.currentSchema.entities.map(\.name))))
        #expect(TimeTrackerModelRegistry.cloudSyncedUserModelNames.contains("DailySummary") == false)
        #expect(TimeTrackerModelRegistry.currentSchema.entity(for: DailySummary.self) == nil)

        let schema = TimeTrackerModelRegistry.currentSchema
        #expect(schema.entity(for: TaskRecurrenceRule.self) != nil)
        #expect(schema.entity(for: TaskRecurrenceOccurrence.self) != nil)
        #expect(schema.entity(for: TaskQuantityGoal.self) != nil)
        #expect(schema.entity(for: TaskQuantityEntry.self) != nil)
        // Every cloud-synced entity must resolve together when the schema is
        // instantiated into a container; the name-set assertions above prove the
        // membership, so no per-model insert/fetch round trip is needed.
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
    func versionEightStoreMigratesToCurrentSchemaWithoutTheLegacyDailySummaryCache() throws {
        let fixture = try LegacyV8DailySummaryStoreFixture.create()

        try fixture.withCurrentContext { context in
            let taskIDs = try context.fetch(FetchDescriptor<TaskNode>()).map(\.id)
            #expect(taskIDs == [fixture.taskID])
            #expect(TimeTrackerModelRegistry.currentSchema.entity(for: DailySummary.self) == nil)
        }
    }

    @Test @MainActor
    func versionNineStoreMigratesInboxSuggestionIdentityAndDismissalState() throws {
        let fixture = try LegacyV9InboxStoreFixture.create()

        try fixture.withCurrentContext { context in
            let items = try context.fetch(FetchDescriptor<InboxItem>())
            let suggestions = try context.fetch(FetchDescriptor<InboxSuggestion>())
            let dismissedItem = try #require(items.first { $0.id == fixture.dismissedItemID })
            let readyItem = try #require(items.first { $0.id == fixture.readyItemID })
            let suggestion = try #require(suggestions.first { $0.id == fixture.suggestionID })

            #expect(dismissedItem.suggestionContextID == fixture.dismissedItemID)
            #expect(dismissedItem.suggestionRevisionID == fixture.dismissedItemID)
            #expect(dismissedItem.dismissedSuggestionRevisionID == fixture.dismissedItemID)
            #expect(
                InboxSuggestionStateService.state(
                    for: dismissedItem,
                    suggestion: nil,
                    isInFlight: false
                ) == .dismissed
            )
            #expect(readyItem.suggestionContextID == fixture.readyItemID)
            #expect(readyItem.suggestionRevisionID == fixture.readyItemID)
            #expect(readyItem.dismissedSuggestionRevisionID == nil)
            #expect(suggestion.inboxItemContextID == fixture.readyItemID)
            #expect(suggestion.inboxItemRevisionID == fixture.readyItemID)
            #expect(suggestion.belongs(to: readyItem))
        }
    }

    @Test @MainActor
    func applyingInboxSuggestionCreatesChecklistWithVisualAndRemovesInboxItem() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Design", parentID: nil, colorHex: "1677FF", iconName: "paintbrush")
        let inboxItem = InboxItem(title: "Polish empty state", deviceID: "test")
        let suggestion = InboxSuggestion(
            inboxItemID: inboxItem.id,
            taskID: task.id,
            reason: "Same design project",
            iconName: "paintbrush",
            colorHex: "1677FF",
            modelID: "gpt-test",
            titleSnapshot: inboxItem.title,
            deviceID: "test"
        )
        context.insert(inboxItem)
        context.insert(suggestion)
        try context.save()

        _ = try StoreScopedInboxCommandCoordinator(
            session: .testHarness(context.container),
            deviceID: "test"
        ).applySuggestion(
            baseline: InboxSuggestionApplyBaseline(item: inboxItem, suggestion: suggestion)
        )

        let freshContext = ModelContext(context.container)
        let checklistItems = try freshContext.fetch(FetchDescriptor<ChecklistItem>())
        let visuals = try freshContext.fetch(FetchDescriptor<ChecklistItemVisual>())
        let inboxItems = try freshContext.fetch(FetchDescriptor<InboxItem>())
        let suggestions = try freshContext.fetch(FetchDescriptor<InboxSuggestion>())
        #expect(checklistItems.map(\.title) == ["Polish empty state"])
        #expect(checklistItems.first?.taskID == task.id)
        #expect(visuals.map(\.iconName) == ["paintbrush"])
        #expect(visuals.map(\.colorHex) == ["1677FF"])
        #expect(visuals.map(\.suggestionTitleSnapshot) == ["Polish empty state"])
        #expect(visuals.map(\.suggestionModelID) == ["gpt-test"])
        #expect(inboxItems.allSatisfy { $0.deletedAt != nil })
        #expect(suggestions.allSatisfy { $0.deletedAt != nil })
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

    @Test @MainActor
    func jsonExportFailureThrowsWithoutMutatingGlobalFeedback() {
        let store = makeTestStore()

        #expect(throws: TimeTrackerStore.StoreError.self) {
            try store.jsonExport()
        }
        #expect(store.errorMessage == nil)
    }
}
