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
    func persistentDeduplicationPrefersTombstoneWhenTimestampsTie() {
        let id = UUID()
        let timestamp = Date(timeIntervalSinceReferenceDate: 100_000)
        let active = TaskNode(title: "Active", parentID: nil, deviceID: "test")
        active.id = id
        active.createdAt = timestamp
        active.updatedAt = timestamp

        let tombstone = TaskNode(title: "Deleted", parentID: nil, deviceID: "test")
        tombstone.id = id
        tombstone.createdAt = timestamp
        tombstone.updatedAt = timestamp
        tombstone.deletedAt = timestamp

        #expect([active, tombstone].deduplicatedByID().first === tombstone)
        #expect([tombstone, active].deduplicatedByID().first === tombstone)
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
    func persistentDeduplicationUsesMutationIDWhenMetadataAndDeviceTie() {
        let id = UUID()
        let timestamp = Date(timeIntervalSinceReferenceDate: 100_000)
        let lowerMutationID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let higherMutationID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = TaskNode(title: "First", parentID: nil, deviceID: "same-device")
        first.id = id
        first.createdAt = timestamp
        first.updatedAt = timestamp
        first.clientMutationID = lowerMutationID
        let second = TaskNode(title: "Second", parentID: nil, deviceID: "same-device")
        second.id = id
        second.createdAt = timestamp
        second.updatedAt = timestamp
        second.clientMutationID = higherMutationID

        #expect([first, second].deduplicatedByID().first === second)
        #expect([second, first].deduplicatedByID().first === second)
    }

    @Test @MainActor
    func timeSegmentDeduplicationIsStableWhenAllSyncMetadataTies() {
        let id = UUID()
        let sessionID = UUID()
        let taskID = UUID()
        let timestamp = Date(timeIntervalSinceReferenceDate: 100_000)
        let manual = TimeSegment(
            sessionID: sessionID,
            taskID: taskID,
            source: .manual,
            deviceID: "same-device",
            startedAt: timestamp
        )
        manual.id = id
        manual.createdAt = timestamp
        manual.updatedAt = timestamp
        let timer = TimeSegment(
            sessionID: sessionID,
            taskID: taskID,
            source: .timer,
            deviceID: "same-device",
            startedAt: timestamp
        )
        timer.id = id
        timer.createdAt = timestamp
        timer.updatedAt = timestamp

        #expect([manual, timer].deduplicatedByID().first === timer)
        #expect([timer, manual].deduplicatedByID().first === timer)
    }

    @Test @MainActor
    func duplicateCleanupKeepsTheCanonicalActiveRowNewerThanItsTombstone() {
        let id = UUID()
        let base = Date(timeIntervalSinceReferenceDate: 100_000)
        let older = TaskNode(title: "Older", parentID: nil, deviceID: "old")
        older.id = id
        older.createdAt = base
        older.updatedAt = base
        let newer = TaskNode(title: "Newer", parentID: nil, deviceID: "new")
        newer.id = id
        newer.createdAt = base.addingTimeInterval(10)
        newer.updatedAt = base.addingTimeInterval(10)
        let cleanupDate = base.addingTimeInterval(20)

        let latest = [older, newer].latestByIDMarkingDuplicatesDeleted(
            now: cleanupDate,
            deviceID: "cleanup"
        )

        #expect(latest[id] === newer)
        #expect(older.deletedAt != nil)
        #expect(newer.deletedAt == nil)
        #expect(newer.updatedAt == cleanupDate)
        #expect([older, newer].deduplicatedByID().first === newer)
    }

    @Test @MainActor
    func duplicateCleanupDoesNotRefreshAnOlderTombstonePastANewerRestore() {
        let id = UUID()
        let base = Date(timeIntervalSinceReferenceDate: 100_000)
        let tombstone = TaskNode(title: "Deleted", parentID: nil, deviceID: "old")
        tombstone.id = id
        tombstone.createdAt = base
        tombstone.updatedAt = base.addingTimeInterval(10)
        tombstone.deletedAt = tombstone.updatedAt
        let originalTombstoneUpdate = tombstone.updatedAt
        let restored = TaskNode(title: "Restored", parentID: nil, deviceID: "new")
        restored.id = id
        restored.createdAt = base
        restored.updatedAt = base.addingTimeInterval(20)

        let latest = [tombstone, restored].latestByIDMarkingDuplicatesDeleted(
            now: base.addingTimeInterval(30),
            deviceID: "cleanup"
        )

        #expect(latest[id] === restored)
        #expect(tombstone.updatedAt == originalTombstoneUpdate)
        #expect([tombstone, restored].deduplicatedByID().first === restored)
    }

    @Test @MainActor
    func modelDefaultsSupportCloudKitCompatibleConstruction() throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Defaults", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test")
        let segment = TimeSegment(sessionID: session.id, taskID: task.id, source: .timer, deviceID: "test")
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        let countdown = CountdownEvent(title: "Launch", date: Date(), deviceID: "test")
        let preference = SyncedPreference(key: AppPreferenceKey.defaultFocusMinutes.rawValue, valueJSON: "25", deviceID: "test")
        let checklistItem = ChecklistItem(taskID: task.id, title: "Checklist", deviceID: "test")
        let checklistVisual = ChecklistItemVisual(checklistItemID: checklistItem.id, iconName: "book", colorHex: "16A34A", deviceID: "test")
        let inboxItem = InboxItem(title: "Inbox", deviceID: "test")
        let inboxSuggestion = InboxSuggestion(
            inboxItemID: inboxItem.id,
            taskID: task.id,
            reason: "Related",
            iconName: "book",
            colorHex: "16A34A",
            modelID: "test",
            titleSnapshot: inboxItem.title,
            deviceID: "test"
        )
        let category = TaskCategory(title: "Work", deviceID: "test")
        let categoryAssignment = TaskCategoryAssignment(taskID: task.id, categoryID: category.id, deviceID: "test")
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
        context.insert(category)
        context.insert(categoryAssignment)
        context.insert(session)
        context.insert(segment)
        context.insert(run)
        context.insert(countdown)
        context.insert(preference)
        context.insert(checklistItem)
        context.insert(checklistVisual)
        context.insert(inboxItem)
        context.insert(inboxSuggestion)
        context.insert(recurrenceRule)
        context.insert(recurrenceOccurrence)
        context.insert(quantityGoal)
        context.insert(quantityEntry)
        try context.save()

        #expect(task.id.uuidString.isEmpty == false)
        #expect(task.statusRaw == LegacyTaskStatusRaw.active)
        #expect(segment.source == .timer)
        #expect(run.state == .planned)
        #expect(countdown.deletedAt == nil)
        #expect(preference.deletedAt == nil)
        #expect(checklistItem.deletedAt == nil)
        #expect(checklistVisual.deletedAt == nil)
        #expect(checklistVisual.suggestionTitleSnapshot == nil)
        #expect(checklistVisual.userEditedAt == nil)
        #expect(inboxSuggestion.deletedAt == nil)
        #expect(inboxSuggestion.destinationKindRaw == "checklist")
        #expect(inboxSuggestion.destinationKind == .checklist)
        #expect(category.includesInForecast)
        #expect(categoryAssignment.deletedAt == nil)
        #expect(recurrenceRule.id == TaskProgressIdentity.recurrenceRuleID(templateTaskID: task.id))
        #expect(recurrenceRule.cadenceRaw == TaskRecurrenceCadence.daily.rawValue)
        #expect(recurrenceRule.isEnabled)
        #expect(recurrenceOccurrence.generatedTaskID == TaskProgressIdentity.generatedTaskID(
            ruleID: recurrenceRule.id,
            dayKey: recurrenceOccurrence.occurrenceDayKey
        ))
        #expect(quantityGoal.id == TaskProgressIdentity.quantityGoalID(taskID: task.id))
        #expect(quantityEntry.quantityGoalID == quantityGoal.id)
        #expect(quantityEntry.deletedAt == nil)
    }

    @Test @MainActor
    func cloudSyncedSchemaIncludesChecklistAndAllUserDataModels() throws {
        let requiredModelNames: Set<String> = [
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
            "TaskQuantityEntry"
        ]

        #expect(requiredModelNames.isSubset(of: TimeTrackerModelRegistry.cloudSyncedUserModelNames))
        #expect(TimeTrackerModelRegistry.cloudSyncedUserModelNames.contains("DailySummary") == false)
        #expect(TimeTrackerModelRegistry.currentSchema.entity(for: DailySummary.self) == nil)

        let schema = TimeTrackerModelRegistry.currentSchema
        #expect(schema.entity(for: TaskRecurrenceRule.self) != nil)
        #expect(schema.entity(for: TaskRecurrenceOccurrence.self) != nil)
        #expect(schema.entity(for: TaskQuantityGoal.self) != nil)
        #expect(schema.entity(for: TaskQuantityEntry.self) != nil)
        #expect(
            TimeTrackerMigrationPlan.schemas.last?.versionIdentifier
                == TimeTrackerSchemaV13.versionIdentifier
        )
        let configuration = ModelConfiguration(
            "TimeTrackerCloudSyncContract",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let task = TaskNode(title: "Cloud task", parentID: nil, deviceID: "test")
        let category = TaskCategory(title: "Cloud category", deviceID: "test")
        let assignment = TaskCategoryAssignment(taskID: task.id, categoryID: category.id, deviceID: "test")
        let checklist = ChecklistItem(taskID: task.id, title: "Cloud checklist", deviceID: "test")
        let checklistVisual = ChecklistItemVisual(checklistItemID: checklist.id, iconName: "book", colorHex: "16A34A", deviceID: "test")
        let inboxItem = InboxItem(title: "Cloud inbox", deviceID: "test")
        let inboxSuggestion = InboxSuggestion(
            inboxItemID: inboxItem.id,
            taskID: task.id,
            reason: "Cloud reason",
            iconName: "book",
            colorHex: "16A34A",
            modelID: "test",
            titleSnapshot: inboxItem.title,
            deviceID: "test"
        )
        let inboxReceipt = InboxCaptureReceipt(
            commandKey: "test.integration\u{1F}\(UUID().uuidString.lowercased())",
            payloadFingerprint: String(repeating: "a", count: 64),
            inboxItemID: inboxItem.id,
            deviceID: "test"
        )
        let preference = SyncedPreference(key: AppPreferenceKey.showGrossAndWallTogether.rawValue, valueJSON: "true", deviceID: "test")
        let recurrenceRule = TaskRecurrenceRule(
            templateTaskID: task.id,
            startDayKey: "2026-07-20",
            timeZoneIdentifier: "UTC",
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
            amount: 25,
            deviceID: "test"
        )

        context.insert(task)
        context.insert(category)
        context.insert(assignment)
        context.insert(checklist)
        context.insert(checklistVisual)
        context.insert(inboxItem)
        context.insert(inboxSuggestion)
        context.insert(inboxReceipt)
        context.insert(preference)
        context.insert(recurrenceRule)
        context.insert(recurrenceOccurrence)
        context.insert(quantityGoal)
        context.insert(quantityEntry)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).map(\.title) == ["Cloud checklist"])
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).map(\.iconName) == ["book"])
        #expect(try context.fetch(FetchDescriptor<InboxItem>()).map(\.title) == ["Cloud inbox"])
        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).map(\.taskID) == [task.id])
        #expect(try context.fetch(FetchDescriptor<InboxCaptureReceipt>()).map(\.inboxItemID) == [inboxItem.id])
        #expect(try context.fetch(FetchDescriptor<TaskCategoryAssignment>()).map(\.categoryID) == [category.id])
        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).map(\.key) == [AppPreferenceKey.showGrossAndWallTogether.rawValue])
        #expect(try context.fetch(FetchDescriptor<TaskRecurrenceRule>()).map(\.templateTaskID) == [task.id])
        #expect(try context.fetch(FetchDescriptor<TaskRecurrenceOccurrence>()).map(\.ruleID) == [recurrenceRule.id])
        #expect(try context.fetch(FetchDescriptor<TaskQuantityGoal>()).map(\.targetAmount) == [50])
        #expect(try context.fetch(FetchDescriptor<TaskQuantityEntry>()).map(\.amount) == [25])
    }

    @Test @MainActor
    func versionEightStoreMigratesToCurrentSchemaWithoutTheLegacyDailySummaryCache() throws {
        let fixture = try LegacyV8DailySummaryStoreFixture.create()
        defer { fixture.remove() }

        try fixture.withCurrentContext { context in
            let taskIDs = try context.fetch(FetchDescriptor<TaskNode>()).map(\.id)
            #expect(taskIDs == [fixture.taskID])
            #expect(TimeTrackerModelRegistry.currentSchema.entity(for: DailySummary.self) == nil)
            #expect(TimeTrackerMigrationPlan.schemas.last?.versionIdentifier == TimeTrackerSchemaV13.versionIdentifier)
        }
    }

    @Test @MainActor
    func versionNineStoreMigratesInboxSuggestionIdentityAndDismissalState() throws {
        let fixture = try LegacyV9InboxStoreFixture.create()
        defer { fixture.remove() }

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
                InboxSuggestionStateService().state(
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

        _ = try InboxCommandHandler().applySuggestion(
            item: inboxItem,
            suggestion: suggestion,
            existingChecklistItems: [],
            context: context,
            deviceID: "test"
        )

        let checklistItems = try context.fetch(FetchDescriptor<ChecklistItem>())
        let visuals = try context.fetch(FetchDescriptor<ChecklistItemVisual>())
        #expect(checklistItems.map(\.title) == ["Polish empty state"])
        #expect(checklistItems.first?.taskID == task.id)
        #expect(visuals.map(\.iconName) == ["paintbrush"])
        #expect(visuals.map(\.colorHex) == ["1677FF"])
        #expect(visuals.map(\.suggestionTitleSnapshot) == ["Polish empty state"])
        #expect(visuals.map(\.suggestionModelID) == ["gpt-test"])
        #expect(inboxItem.deletedAt != nil)
        #expect(suggestion.deletedAt != nil)
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
    func jsonExportIncludesCloudSyncedData() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "JSON Task", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 2_000)
        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            note: "Export note"
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let json = try store.jsonExport()

        #expect(json.contains("\"format\" : \"timetracker.cloudSyncedData\""))
        #expect(json.contains("\"tasks\""))
        #expect(json.contains("\"segments\""))
        #expect(json.contains("JSON Task"))
        #expect(json.contains("Export note"))
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
