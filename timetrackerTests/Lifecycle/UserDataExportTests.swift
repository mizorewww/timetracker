import Foundation
import SwiftData
import Testing
@testable import timetracker

@MainActor
struct UserDataExportTests {
    @Test
    func exportIncludesBusinessRowsAndExcludesSensitivePreferences() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test")
            .createTask(title: "Exported task", parentID: nil)
        context.insert(SyncedPreference(
            key: SyncedPreferenceService.legacyLLMAPIKey,
            valueJSON: "\"secret-key\"",
            deviceID: "test"
        ))
        context.insert(SyncedPreference(
            key: AppPreferenceKey.allowParallelTimers.rawValue,
            valueJSON: "true",
            deviceID: "test"
        ))
        try context.save()

        let json = try UserDataExport.encodedJSON(container: context.container)

        #expect(json.contains("\"timetracker.cloudSyncedData\""))
        #expect(json.contains(task.id.uuidString))
        #expect(json.contains(AppPreferenceKey.allowParallelTimers.rawValue))
        #expect(json.contains("secret-key") == false)
    }

    /// A new synced model must get an export section (or a deliberate entry
    /// here); otherwise its data silently disappears from exports.
    @Test
    func everySyncedModelHasAnExportSection() throws {
        let sectionByModel = [
            "TaskNode": "tasks",
            "TaskCategory": "taskCategories",
            "TaskCategoryAssignment": "taskCategoryAssignments",
            "TimeSession": "sessions",
            "TimeSegment": "segments",
            "PomodoroRun": "pomodoroRuns",
            "CountdownEvent": "countdownEvents",
            "SyncedPreference": "syncedPreferences",
            "ChecklistItem": "checklistItems",
            "ChecklistItemVisual": "checklistItemVisuals",
            "InboxItem": "inboxItems",
            "InboxSuggestion": "inboxSuggestions",
            "InboxCaptureReceipt": "inboxCaptureReceipts",
            "TaskRecurrenceRule": "taskRecurrenceRules",
            "TaskRecurrenceOccurrence": "taskRecurrenceOccurrences",
            "TaskQuantityGoal": "taskQuantityGoals",
            "TaskQuantityEntry": "taskQuantityEntries",
        ]
        let context = try makeTestContext()

        let json = try UserDataExport.encodedJSON(container: context.container)
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        let data = try #require(root["data"] as? [String: Any])

        #expect(Set(sectionByModel.keys) == TimeTrackerModelRegistry.cloudSyncedUserModelNames)
        #expect(Set(data.keys) == Set(sectionByModel.values))
    }

    @Test
    func jsonExportFailureThrowsWithoutMutatingGlobalFeedback() {
        let store = makeTestStore()

        #expect(throws: TimeTrackerStore.StoreError.self) {
            try store.jsonExport()
        }
        #expect(store.errorMessage == nil)
    }
}
