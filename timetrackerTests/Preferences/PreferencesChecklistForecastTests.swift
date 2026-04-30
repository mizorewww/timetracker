import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct PreferencesChecklistForecastTests {
    @Test @MainActor
    func syncedPreferenceMigrationImportsLegacyUserDefaults() throws {
        let defaults = UserDefaults.standard
        let keys = AppPreferenceKey.allCases.map(\.rawValue) + [SyncedPreferenceService.migrationKey]
        let previousValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for (key, value) in previousValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let pinnedID = UUID()
        defaults.removeObject(forKey: SyncedPreferenceService.migrationKey)
        defaults.set("dark", forKey: AppPreferenceKey.preferredColorScheme.rawValue)
        defaults.set("deep", forKey: AppPreferenceKey.pomodoroDefaultMode.rawValue)
        defaults.set(50, forKey: AppPreferenceKey.defaultFocusMinutes.rawValue)
        defaults.set(10, forKey: AppPreferenceKey.defaultBreakMinutes.rawValue)
        defaults.set(4, forKey: AppPreferenceKey.defaultPomodoroRounds.rawValue)
        defaults.set(false, forKey: AppPreferenceKey.allowParallelTimers.rawValue)
        defaults.set(false, forKey: AppPreferenceKey.showGrossAndWallTogether.rawValue)
        defaults.set(false, forKey: AppPreferenceKey.cloudSyncEnabled.rawValue)
        defaults.set(pinnedID.uuidString, forKey: AppPreferenceKey.quickStartTaskIDs.rawValue)

        let context = try makeTestContext()
        try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(context: context, deviceID: "test")
        let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
        let preferences = AppPreferences(syncedPreferences: stored)

        #expect(stored.count == AppPreferenceKey.allCases.count)
        #expect(preferences.preferredColorScheme == "dark")
        #expect(preferences.pomodoroDefaultMode == "deep")
        #expect(preferences.defaultFocusMinutes == 50)
        #expect(preferences.defaultBreakMinutes == 10)
        #expect(preferences.defaultPomodoroRounds == 4)
        #expect(preferences.allowParallelTimers == false)
        #expect(preferences.showGrossAndWallTogether == false)
        #expect(preferences.cloudSyncEnabled == false)
        #expect(preferences.quickStartTaskIDs == [pinnedID])
    }

    @Test @MainActor
    func settingsWriteSyncedPreferencesAndCloudMirror() throws {
        let defaults = UserDefaults.standard
        let previousMigration = defaults.object(forKey: SyncedPreferenceService.migrationKey)
        let previousCloud = defaults.object(forKey: AppCloudSync.enabledKey)
        defer {
            if let previousMigration {
                defaults.set(previousMigration, forKey: SyncedPreferenceService.migrationKey)
            } else {
                defaults.removeObject(forKey: SyncedPreferenceService.migrationKey)
            }
            if let previousCloud {
                defaults.set(previousCloud, forKey: AppCloudSync.enabledKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.enabledKey)
            }
        }

        defaults.set(true, forKey: SyncedPreferenceService.migrationKey)
        let context = try makeTestContext()
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        let pinnedID = UUID()

        store.setDefaultFocusMinutes(45)
        store.setDefaultBreakMinutes(12)
        store.setDefaultPomodoroRounds(3)
        store.setAllowParallelTimers(false)
        store.setShowGrossAndWallTogether(false)
        store.setCloudSyncEnabled(false)
        store.setQuickStartTaskIDs([pinnedID])

        let preferences = AppPreferences(syncedPreferences: try context.fetch(FetchDescriptor<SyncedPreference>()))
        #expect(preferences.defaultFocusMinutes == 45)
        #expect(preferences.defaultBreakMinutes == 12)
        #expect(preferences.defaultPomodoroRounds == 3)
        #expect(preferences.allowParallelTimers == false)
        #expect(preferences.showGrossAndWallTogether == false)
        #expect(preferences.cloudSyncEnabled == false)
        #expect(preferences.quickStartTaskIDs == [pinnedID])
        #expect(defaults.bool(forKey: AppCloudSync.enabledKey) == false)
    }

    @Test
    func syncFeedbackExplainsUserVisibleState() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        var preferences = AppPreferences.defaults
        preferences.cloudSyncEnabled = true

        let cloudStatus = SyncStatus(
            mode: "iCloud",
            containerIdentifier: "iCloud.test",
            deviceID: "test",
            lastError: nil,
            accountStatus: "Available"
        )
        let recentFeedback = cloudStatus.feedback(
            preferences: preferences,
            isChecking: false,
            lastRefreshAt: now.addingTimeInterval(-45),
            now: now
        )
        #expect(recentFeedback.state == .recentlySynced)
        #expect(recentFeedback.message.isEmpty == false)

        let checkingFeedback = cloudStatus.feedback(
            preferences: preferences,
            isChecking: true,
            lastRefreshAt: nil,
            now: now
        )
        #expect(checkingFeedback.state == .syncing)

        preferences.cloudSyncEnabled = false
        let restartFeedback = cloudStatus.feedback(
            preferences: preferences,
            isChecking: false,
            lastRefreshAt: nil,
            now: now
        )
        #expect(restartFeedback.state == .needsRestart)

        let failedStatus = SyncStatus(
            mode: "Local fallback",
            containerIdentifier: "iCloud.test",
            deviceID: "test",
            lastError: "CloudKit failed",
            accountStatus: "Available"
        )
        preferences.cloudSyncEnabled = true
        let failedFeedback = failedStatus.feedback(
            preferences: preferences,
            isChecking: false,
            lastRefreshAt: nil,
            now: now
        )
        #expect(failedFeedback.state == .failed)
        #expect(failedFeedback.message.contains("CloudKit failed"))
    }

    @Test @MainActor
    func checklistDraftsPersistCompletionSortingAndSoftDelete() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Launch", parentID: nil, colorHex: nil, iconName: nil)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        var firstDraft = TaskEditorDraft(task: task, checklistItems: [])
        firstDraft.checklistItems = [
            ChecklistEditorDraft(title: "Write copy"),
            ChecklistEditorDraft(title: "Ship build")
        ]
        store.saveTaskDraft(firstDraft)
        #expect(store.checklistItems(for: task.id).map(\.title) == ["Write copy", "Ship build"])

        let existing = store.checklistItems(for: task.id)
        var secondDraft = TaskEditorDraft(task: task, checklistItems: existing)
        secondDraft.checklistItems = [
            ChecklistEditorDraft(item: existing[1]),
            ChecklistEditorDraft(item: existing[0])
        ]
        secondDraft.checklistItems[0].isCompleted = true
        secondDraft.checklistItems.removeLast()
        store.saveTaskDraft(secondDraft)

        let activeItems = store.checklistItems(for: task.id)
        let allItems = try context.fetch(FetchDescriptor<ChecklistItem>()).filter { $0.taskID == task.id }
        #expect(activeItems.map(\.title) == ["Ship build"])
        #expect(activeItems.first?.isCompleted == true)
        #expect(activeItems.first?.completedAt != nil)
        #expect(allItems.filter { $0.deletedAt != nil }.count == 1)

        let keptItem = try #require(activeItems.first)
        store.toggleChecklistItem(keptItem)
        #expect(store.checklistItems(for: task.id).first?.isCompleted == false)
        #expect(store.checklistItems(for: task.id).first?.completedAt == nil)
    }

    @Test
    func checklistOrderingRejectsMovesAcrossCompletionBoundary() {
        let service = ChecklistOrderingService()
        let openA = UUID()
        let openB = UUID()
        let doneA = UUID()
        let doneB = UUID()
        let elements = [
            ChecklistOrderingElement(id: openA, isCompleted: false),
            ChecklistOrderingElement(id: openB, isCompleted: false),
            ChecklistOrderingElement(id: doneA, isCompleted: true),
            ChecklistOrderingElement(id: doneB, isCompleted: true)
        ]

        #expect(service.reorderedIDs(elements: elements, sourceOffsets: IndexSet(integer: 1), destination: 0) == [openB, openA, doneA, doneB])
        #expect(service.reorderedIDs(elements: elements, sourceOffsets: IndexSet(integer: 1), destination: 3) == nil)
        #expect(service.reorderedIDs(elements: elements, sourceOffsets: IndexSet(integer: 2), destination: 1) == nil)
        #expect(service.reorderedIDs(elements: elements, sourceOffsets: IndexSet(integer: 2), destination: 4) == [openA, openB, doneB, doneA])
    }

    @Test @MainActor
    func checklistReorderPersistsWithinCompletionGroups() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Checklist Order", parentID: nil, colorHex: nil, iconName: nil)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        store.addChecklistItem(taskID: task.id, title: "Open A")
        store.addChecklistItem(taskID: task.id, title: "Open B")
        store.addChecklistItem(taskID: task.id, title: "Done A")
        let doneA = try #require(store.checklistItems(for: task.id).last)
        store.toggleChecklistItem(doneA)

        store.reorderChecklistItems(taskID: task.id, sourceOffsets: IndexSet(integer: 1), destination: 0)
        #expect(store.checklistItems(for: task.id).map(\.title) == ["Open B", "Open A", "Done A"])

        store.reorderChecklistItems(taskID: task.id, sourceOffsets: IndexSet(integer: 1), destination: 3)
        #expect(store.checklistItems(for: task.id).map(\.title) == ["Open B", "Open A", "Done A"])
    }
}
