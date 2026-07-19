import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct DataMaintenanceLifecycleTests {
    @Test @MainActor
    func resetDataHidesAllUserFactsAndRetainsCloudDeletionTombstones() throws {
        let defaults = UserDefaults.standard
        let automaticSuggestionsKey = AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
        let previousAutomaticSuggestions = defaults.object(forKey: automaticSuggestionsKey)
        defer {
            if let previousAutomaticSuggestions {
                defaults.set(previousAutomaticSuggestions, forKey: automaticSuggestionsKey)
            } else {
                defaults.removeObject(forKey: automaticSuggestionsKey)
            }
        }
        let context = try makeTestContext()
        let task = TaskNode(title: "Reset me", parentID: nil, deviceID: "test")
        let category = TaskCategory(title: "Reset category", deviceID: "test")
        let assignment = TaskCategoryAssignment(taskID: task.id, categoryID: category.id, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .manual, deviceID: "test")
        session.endedAt = Date()
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .manual,
            deviceID: "test",
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date()
        )
        let pomodoro = PomodoroRun(taskID: task.id, deviceID: "test")
        let countdown = CountdownEvent(title: "Reset countdown", date: Date(), deviceID: "test")
        let preference = SyncedPreference(key: AppPreferenceKey.showGrossAndWallTogether.rawValue, valueJSON: "true", deviceID: "test")
        let checklistItem = ChecklistItem(taskID: task.id, title: "Reset checklist", deviceID: "test")
        let checklistVisual = ChecklistItemVisual(checklistItemID: checklistItem.id, deviceID: "test")
        let inboxItem = InboxItem(title: "Reset inbox", deviceID: "test")
        let inboxSuggestion = InboxSuggestion(inboxItemID: inboxItem.id, taskID: task.id, titleSnapshot: inboxItem.title, deviceID: "test")
        let inboxReceipt = InboxCaptureReceipt(
            commandKey: "test.integration\u{1F}\(UUID().uuidString.lowercased())",
            payloadFingerprint: String(repeating: "a", count: 64),
            inboxItemID: inboxItem.id,
            deviceID: "test"
        )

        context.insert(task)
        context.insert(category)
        context.insert(assignment)
        context.insert(session)
        context.insert(segment)
        context.insert(pomodoro)
        context.insert(countdown)
        context.insert(preference)
        context.insert(checklistItem)
        context.insert(checklistVisual)
        context.insert(inboxItem)
        context.insert(inboxSuggestion)
        context.insert(inboxReceipt)
        try context.save()

        let credentialStore = ResetTestCredentialStore()
        try credentialStore.writeAPIKey("private-test-key")
        defaults.set(true, forKey: automaticSuggestionsKey)
        let healthPreferences = TestAppleHealthTimelinePreferenceStore(
            isTimelineEnabled: true
        )
        let store = makeTestStore(
            llmCredentialStore: credentialStore,
            appleHealthTimelinePreferenceStore: healthPreferences
        )
        store.configureIfNeeded(context: context)
        store.selectedTaskID = task.id
        store.tasksRoute = .detail(taskID: task.id)
        let healthInterval = DateInterval(
            start: Date().addingTimeInterval(-600),
            end: Date()
        )
        store.appleHealthTimelineItems = [
            AppleHealthTimelineItem(
                id: .appleHealthWorkout(UUID()),
                subject: .appleHealthWorkout(.walking),
                interval: healthInterval
            ),
        ]
        store.appleHealthTimelineState = .content(
            interval: healthInterval,
            refreshedAt: Date(),
            itemCount: 1
        )

        store.clearAllData()

        #expect(store.errorMessage == nil)
        #expect(store.tasks.isEmpty)
        #expect(store.allSegments.isEmpty)
        #expect(store.pomodoroRuns.isEmpty)
        #expect(store.countdownEvents.isEmpty)
        #expect(store.syncedPreferences.isEmpty)
        #expect(try credentialStore.readAPIKey() == nil)
        #expect(defaults.object(forKey: automaticSuggestionsKey) == nil)
        #expect(store.selectedTaskID == nil)
        #expect(store.tasksRoute == nil)
        #expect(healthPreferences.isTimelineEnabled == false)
        #expect(store.isAppleHealthTimelineEnabled == false)
        #expect(store.appleHealthTimelineItems.isEmpty)
        #expect(store.appleHealthTimelineState == .unavailable)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<TaskCategory>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<TaskCategoryAssignment>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<TimeSession>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<PomodoroRun>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<CountdownEvent>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<InboxItem>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).allSatisfy { $0.deletedAt != nil })
        #expect(try context.fetch(FetchDescriptor<InboxCaptureReceipt>()).allSatisfy { $0.deletedAt != nil })

        let deletionSnapshot = try SyncDataSnapshot.capture(context: context)
        #expect(deletionSnapshot.hasProtectableUserContent)
        #expect(deletionSnapshot.hasVisibleUserContent == false)
    }

    @Test @MainActor
    func optimizeDatabasePreservesLedgerRowsForTombstonedTasks() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Temporary Client", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date().addingTimeInterval(-1_800)
        let segment = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            note: nil
        )
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        run.sessionID = segment.sessionID
        run.state = .completed
        context.insert(run)
        let tombstonedAt = task.updatedAt.addingTimeInterval(1)
        task.deletedAt = tombstonedAt
        task.updatedAt = tombstonedAt
        task.deviceID = "legacy-sync"
        task.clientMutationID = UUID()
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.allSegments.count == 1)

        let removedCount = try store.optimizeDatabase()

        #expect(removedCount == 0)
        #expect(try timeRepository.allSegments().contains { $0.id == segment.id })
        #expect(try timeRepository.sessions().contains { $0.id == segment.sessionID })
        #expect(try context.fetch(FetchDescriptor<PomodoroRun>()).contains { $0.id == run.id })
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).contains { $0.id == task.id && $0.deletedAt != nil })
    }

    @Test @MainActor
    func optimizeDatabasePreservesVisibleOrphansDuringStagedCloudImport() throws {
        let context = try makeTestContext()
        let missingTaskID = UUID()
        let session = TimeSession(taskID: missingTaskID, source: .manual, deviceID: "test")
        session.endedAt = Date()
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: missingTaskID,
            source: .manual,
            deviceID: "test",
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date()
        )
        context.insert(session)
        context.insert(segment)
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let removedCount = try store.optimizeDatabase()

        #expect(removedCount == 0)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).contains { $0.id == segment.id })
        #expect(try context.fetch(FetchDescriptor<TimeSession>()).contains { $0.id == session.id })
    }

    @Test @MainActor
    func optimizeDatabasePropagatesFailureWithoutPublishingGlobalError() {
        let store = makeTestStore()

        do {
            _ = try store.optimizeDatabase()
            Issue.record("An unconfigured store must not report a successful zero-row cleanup")
        } catch {
            #expect(error.localizedDescription.isEmpty == false)
            #expect(store.errorMessage == nil)
        }
    }

    @Test @MainActor
    func optimizeDatabaseRollsBackWhenThePersistentStoreRejectsSaving() throws {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: AppCloudSync.modeKey)
        defaults.set(AppCloudSync.modeUITest, forKey: AppCloudSync.modeKey)
        defer {
            if let previousMode {
                defaults.set(previousMode, forKey: AppCloudSync.modeKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.modeKey)
            }
        }

        let directory = FileManager.default.temporaryDirectory.appending(
            path: "DatabaseMaintenanceSaveFailureTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "TimeTracker.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let taskID = UUID()

        do {
            let writableConfiguration = ModelConfiguration(
                "WritableDatabaseMaintenanceSaveFailure",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let writableContainer = try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [writableConfiguration]
            )
            let writableContext = ModelContext(writableContainer)
            let task = TaskNode(title: "Keep after failed cleanup", parentID: nil, deviceID: "test")
            task.id = taskID
            task.deletedAt = Date().addingTimeInterval(
                -DatabaseMaintenanceService.defaultTombstoneRetention - 1
            )
            task.updatedAt = task.deletedAt ?? task.updatedAt
            writableContext.insert(task)
            try writableContext.save()
        }

        let readOnlyConfiguration = ModelConfiguration(
            "ReadOnlyDatabaseMaintenanceSaveFailure",
            schema: schema,
            url: storeURL,
            allowsSave: false,
            cloudKitDatabase: .none
        )
        let readOnlyContainer = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [readOnlyConfiguration]
        )
        let store = makeTestStore()
        store.configureRepositoriesIfNeeded(context: ModelContext(readOnlyContainer))

        do {
            _ = try store.optimizeDatabase()
            Issue.record("A read-only store must reject cleanup instead of reporting success")
        } catch {
            #expect(store.errorMessage == nil)
        }

        let verificationContext = ModelContext(readOnlyContainer)
        let remainingTasks = try verificationContext.fetch(FetchDescriptor<TaskNode>())
        #expect(remainingTasks.contains { $0.id == taskID && $0.deletedAt != nil })
    }

    @Test @MainActor
    func optimizeDatabaseDoesNotDeleteVisibleRelationshipRowsBeforeTheirParentsImport() throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Existing", parentID: nil, deviceID: "test")
        let missingTaskID = UUID()
        let missingCategoryID = UUID()
        let missingSessionID = UUID()
        let missingInboxItemID = UUID()
        let orphanSegment = TimeSegment(
            sessionID: missingSessionID,
            taskID: task.id,
            source: .manual,
            deviceID: "test",
            startedAt: Date().addingTimeInterval(-300),
            endedAt: Date()
        )
        let orphanAssignment = TaskCategoryAssignment(
            taskID: task.id,
            categoryID: missingCategoryID,
            deviceID: "test"
        )
        let orphanChecklistItem = ChecklistItem(
            taskID: missingTaskID,
            title: "Orphan checklist",
            deviceID: "test"
        )
        let orphanVisual = ChecklistItemVisual(
            checklistItemID: orphanChecklistItem.id,
            deviceID: "test"
        )
        let orphanSuggestion = InboxSuggestion(
            inboxItemID: missingInboxItemID,
            taskID: task.id,
            titleSnapshot: "Orphan suggestion",
            deviceID: "test"
        )
        context.insert(task)
        context.insert(orphanSegment)
        context.insert(orphanAssignment)
        context.insert(orphanChecklistItem)
        context.insert(orphanVisual)
        context.insert(orphanSuggestion)
        try context.save()

        let removedCount = try DatabaseMaintenanceService().optimizeDatabase(
            context: context,
            allowsPermanentTombstonePurge: true
        )

        #expect(removedCount == 0)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).map(\.id) == [task.id])
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<TaskCategoryAssignment>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ChecklistItemVisual>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<InboxSuggestion>()).count == 1)
    }

    @Test @MainActor
    func optimizeDatabasePurgesOnlyExpiredTombstoneGraphs() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Long deleted task", parentID: nil, colorHex: nil, iconName: nil)
        let segment = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            endedAt: Date(timeIntervalSinceReferenceDate: 1_600),
            note: nil
        )
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        run.sessionID = segment.sessionID
        context.insert(run)
        let now = Date(timeIntervalSinceReferenceDate: 10_000_000)
        task.deletedAt = now.addingTimeInterval(-DatabaseMaintenanceService.defaultTombstoneRetention - 1)
        task.updatedAt = task.deletedAt ?? task.updatedAt
        try context.save()

        let removedCount = try DatabaseMaintenanceService().optimizeDatabase(
            context: context,
            now: now,
            allowsPermanentTombstonePurge: true
        )

        #expect(removedCount == 4)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PomodoroRun>()).isEmpty)
    }

    @Test @MainActor
    func optimizeDatabasePurgesReceiptsWhoseExpiredInboxItemWasRemoved() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let expiredAt = now.addingTimeInterval(-DatabaseMaintenanceService.defaultTombstoneRetention - 1)
        let item = InboxItem(title: "Expired capture", deviceID: "test")
        item.deletedAt = expiredAt
        item.updatedAt = expiredAt
        let receipt = InboxCaptureReceipt(
            commandKey: "test.integration\u{1F}\(UUID().uuidString.lowercased())",
            payloadFingerprint: String(repeating: "a", count: 64),
            inboxItemID: item.id,
            deviceID: "test"
        )
        context.insert(item)
        context.insert(receipt)
        try context.save()

        let removedCount = try DatabaseMaintenanceService().optimizeDatabase(
            context: context,
            now: now,
            allowsPermanentTombstonePurge: true
        )

        #expect(removedCount == 2)
        #expect(try context.fetch(FetchDescriptor<InboxItem>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<InboxCaptureReceipt>()).isEmpty)
        #expect(try SyncDataSnapshot.capture(context: context).inboxCaptureReceipts == [])
    }

    @Test @MainActor
    func optimizeDatabaseStreamsLeafPurgesAcrossFetchBatches() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let expiredAt = now.addingTimeInterval(-DatabaseMaintenanceService.defaultTombstoneRetention - 1)

        for index in 0..<7 {
            let event = CountdownEvent(title: "Expired \(index)", date: now, deviceID: "test")
            event.deletedAt = expiredAt
            event.updatedAt = expiredAt
            context.insert(event)
        }
        let recentTombstone = CountdownEvent(title: "Recent tombstone", date: now, deviceID: "test")
        recentTombstone.deletedAt = now.addingTimeInterval(-60)
        recentTombstone.updatedAt = recentTombstone.deletedAt ?? recentTombstone.updatedAt
        let visible = CountdownEvent(title: "Visible", date: now, deviceID: "test")
        context.insert(recentTombstone)
        context.insert(visible)
        try context.save()

        let removedCount = try DatabaseMaintenanceService().optimizeDatabase(
            context: context,
            now: now,
            allowsPermanentTombstonePurge: true,
            fetchBatchSize: 2
        )

        #expect(removedCount == 7)
        let remaining = try context.fetch(FetchDescriptor<CountdownEvent>())
        #expect(Set(remaining.map(\.id)) == [recentTombstone.id, visible.id])
    }

    @Test @MainActor
    func optimizeDatabasePreservesNewerVisibleDuplicateOfExpiredTombstone() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let expiredAt = now.addingTimeInterval(-DatabaseMaintenanceService.defaultTombstoneRetention - 1)
        let expired = TaskNode(title: "Expired duplicate", parentID: nil, deviceID: "older")
        expired.deletedAt = expiredAt
        expired.updatedAt = expiredAt
        let restored = TaskNode(title: "Restored winner", parentID: nil, deviceID: "newer")
        restored.id = expired.id
        restored.updatedAt = expiredAt.addingTimeInterval(1)
        context.insert(expired)
        context.insert(restored)
        try context.save()

        let removedCount = try DatabaseMaintenanceService().optimizeDatabase(
            context: context,
            now: now,
            allowsPermanentTombstonePurge: true,
            fetchBatchSize: 2
        )

        #expect(removedCount == 0)
        let duplicates = try context.fetch(FetchDescriptor<TaskNode>())
        #expect(duplicates.count == 2)
        #expect(duplicates.visibleDeduplicatedByID().first?.title == "Restored winner")
    }

    @Test @MainActor
    func optimizeDatabasePreservesExpiredTombstonesWhenCloudCanResume() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 10_000_000)
        let task = TaskNode(title: "Offline deletion guard", parentID: nil, deviceID: "test")
        task.deletedAt = now.addingTimeInterval(-DatabaseMaintenanceService.defaultTombstoneRetention - 1)
        task.updatedAt = task.deletedAt ?? task.updatedAt
        context.insert(task)
        try context.save()

        let removedCount = try DatabaseMaintenanceService().optimizeDatabase(
            context: context,
            now: now,
            allowsPermanentTombstonePurge: false
        )

        #expect(removedCount == 0)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).contains { $0.id == task.id })
    }
}

private final class ResetTestCredentialStore: LLMCredentialStoring {
    private var apiKey: String?

    func readAPIKey() throws -> String? {
        apiKey
    }

    func writeAPIKey(_ apiKey: String) throws {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = normalized.isEmpty ? nil : normalized
    }
}
