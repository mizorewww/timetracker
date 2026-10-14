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
}
