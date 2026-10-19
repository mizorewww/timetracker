import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct ClearAllDataCommandTests {
    private static let localDefaultsKeys = [
        AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled,
        "TimeTrackerAutomaticDemoSeedingDisabled",
    ]

    @Test
    func clearAllDataTombstonesEveryRowOfEveryCurrentModelAndLocalSettings() throws {
        let savedDefaults = Self.saveLocalDefaults()
        defer { Self.restoreLocalDefaults(savedDefaults) }
        let context = try makeTestContext()
        try insertOneRowOfEveryModel(into: context)
        for model in TimeTrackerModelRegistry.currentModels {
            #expect(try rows(of: model, in: context).isEmpty == false, "\(model) has no seeded row")
        }
        let credentialStore = InMemoryCredentialStore(apiKey: "secret")
        AppDefaults.shared.set(false, forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled)
        let store = TimeTrackerStore(
            llmCredentialStore: credentialStore,
            writeAuthorization: .isolatedTestHarness
        )
        store.configureRepositoriesIfNeeded(context: context)

        try store.clearAllData()

        let verificationContext = ModelContext(context.container)
        for model in TimeTrackerModelRegistry.currentModels {
            let remaining = try rows(of: model, in: verificationContext)
            #expect(remaining.isEmpty == false)
            #expect(remaining.allSatisfy { $0.deletedAt != nil }, "\(model) still has a visible row")
        }
        #expect(try credentialStore.readAPIKey() == nil)
        #expect(AppDefaults.shared.object(forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled) == nil)
    }

    @Test
    func failedClearRestoresTheAPIKeyAndAutomaticSuggestionSetting() throws {
        let savedDefaults = Self.saveLocalDefaults()
        defer { Self.restoreLocalDefaults(savedDefaults) }
        let storeURL = try makeStoreDirectory().appending(path: "clear-all.store")
        let schema = TimeTrackerModelRegistry.currentSchema
        let taskID = UUID()
        try initializeWritableStore(at: storeURL, schema: schema) { context in
            let task = TaskNode(title: "Keep", parentID: nil, deviceID: "seed")
            task.id = taskID
            context.insert(task)
        }
        let context = try ModelContext(makeReadOnlyContainer(at: storeURL, schema: schema))
        let credentialStore = InMemoryCredentialStore(apiKey: "secret")
        AppDefaults.shared.set(false, forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled)
        let store = TimeTrackerStore(
            llmCredentialStore: credentialStore,
            writeAuthorization: .isolatedTestHarness
        )
        store.configureRepositoriesIfNeeded(context: context)

        #expect(throws: (any Error).self) {
            try store.clearAllData()
        }

        #expect(try credentialStore.readAPIKey() == "secret")
        #expect(AppDefaults.shared.object(forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled) as? Bool == false)
        let task = try #require(
            ModelContext(context.container).fetch(FetchDescriptor<TaskNode>()).first { $0.id == taskID }
        )
        #expect(task.deletedAt == nil)
    }

    private func insertOneRowOfEveryModel(into context: ModelContext) throws {
        let deviceID = "seed"
        let now = Date()
        let task = TaskNode(title: "Work", parentID: nil, deviceID: deviceID)
        let category = TaskCategory(title: "Career", deviceID: deviceID)
        let session = TimeSession(taskID: task.id, source: .manual, deviceID: deviceID, startedAt: now)
        let checklistItem = ChecklistItem(
            taskID: task.id,
            title: "Step",
            isCompleted: false,
            sortOrder: 0,
            deviceID: deviceID
        )
        let inboxItem = InboxItem(title: "Idea", deviceID: deviceID)
        let rule = TaskRecurrenceRule(
            templateTaskID: task.id,
            startDayKey: "2026-01-01",
            timeZoneIdentifier: "UTC",
            deviceID: deviceID
        )
        let models: [any PersistentModel] = [
            task,
            category,
            TaskCategoryAssignment(taskID: task.id, categoryID: category.id, deviceID: deviceID),
            session,
            TimeSegment(
                sessionID: session.id,
                taskID: task.id,
                source: .manual,
                deviceID: deviceID,
                startedAt: now
            ),
            PomodoroRun(taskID: task.id, focus: 1500, breakSeconds: 300, targetRounds: 1, deviceID: deviceID),
            CountdownEvent(title: "Launch", date: now, deviceID: deviceID),
            SyncedPreference(key: "Example", valueJSON: "1", deviceID: deviceID),
            checklistItem,
            ChecklistItemVisual(
                checklistItemID: checklistItem.id,
                iconName: "circle",
                colorHex: "1677FF",
                deviceID: deviceID
            ),
            inboxItem,
            InboxSuggestion(inboxItemID: inboxItem.id, taskID: task.id, titleSnapshot: "Idea", deviceID: deviceID),
            InboxCaptureReceipt(
                commandKey: "capture",
                payloadFingerprint: "idea",
                inboxItemID: inboxItem.id,
                deviceID: deviceID
            ),
            rule,
            TaskRecurrenceOccurrence(
                ruleID: rule.id,
                templateTaskID: task.id,
                occurrenceDayKey: "2026-01-01",
                timeZoneIdentifier: "UTC",
                deviceID: deviceID
            ),
            TaskQuantityGoal(taskID: task.id, targetAmount: 3, unitLabel: "pages", deviceID: deviceID),
            TaskQuantityEntry(id: UUID(), taskID: task.id, amount: 1, deviceID: deviceID),
        ]
        for model in models {
            context.insert(model)
        }
        try context.save()
    }

    private func rows<Model: PersistentModel>(
        of _: Model.Type,
        in context: ModelContext
    ) throws -> [any SoftDeletablePersistentUUIDModel] {
        try context.fetch(FetchDescriptor<Model>()).map { model in
            try #require(model as? any SoftDeletablePersistentUUIDModel)
        }
    }

    private static func saveLocalDefaults() -> [String: Any] {
        localDefaultsKeys.reduce(into: [:]) { result, key in
            result[key] = AppDefaults.shared.object(forKey: key)
        }
    }

    private static func restoreLocalDefaults(_ values: [String: Any]) {
        for key in localDefaultsKeys {
            if let value = values[key] {
                AppDefaults.shared.set(value, forKey: key)
            } else {
                AppDefaults.shared.removeObject(forKey: key)
            }
        }
    }
}

private final class InMemoryCredentialStore: LLMCredentialStoring {
    private var apiKey: String?

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    func readAPIKey() throws -> String? {
        apiKey
    }

    func writeAPIKey(_ apiKey: String) throws {
        self.apiKey = apiKey.isEmpty ? nil : apiKey
    }
}
