import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreSyncConflictTests {
    @Test @MainActor
    func cloudImportAfterLocalSnapshotPromptsAndUploadRestoresLocalData() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let task = TaskNode(title: "Local plan", parentID: nil, deviceID: "test")
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)

            task.title = "Cloud plan"
            task.updatedAt = Date().addingTimeInterval(60)
            try context.save()

            let prompt = try #require(try service.handleCloudImport(context: context))
            #expect(prompt.localSummary.isEmpty == false)
            #expect(prompt.cloudSummary.isEmpty == false)

            try service.resolve(.uploadLocal, context: context)

            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            #expect(tasks.map(\.title) == ["Local plan"])
            #expect(service.prompt() == nil)
        }
    }

    @Test @MainActor
    func cloudImportConflictCanAcceptCloudData() throws {
        try withCloudSyncMode {
            let context = try makeTestContext()
            let task = TaskNode(title: "Local plan", parentID: nil, deviceID: "test")
            context.insert(task)
            try context.save()

            let service = SyncConflictService(stateURL: temporaryStateURL())
            #expect(try service.bootstrap(context: context) == nil)

            task.title = "Cloud plan"
            task.updatedAt = Date().addingTimeInterval(60)
            try context.save()

            _ = try #require(try service.handleCloudImport(context: context))
            try service.resolve(.downloadCloud, context: context)

            let tasks = try context.fetch(FetchDescriptor<TaskNode>())
            #expect(tasks.map(\.title) == ["Cloud plan"])
            #expect(service.prompt() == nil)
        }
    }

    private func temporaryStateURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeTrackerSyncConflictTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        return url
    }

    private func withCloudSyncMode(_ body: () throws -> Void) throws {
        let defaults = UserDefaults.standard
        let previousMode = defaults.string(forKey: AppCloudSync.modeKey)
        defaults.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
        defer {
            if let previousMode {
                defaults.set(previousMode, forKey: AppCloudSync.modeKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.modeKey)
            }
        }
        try body()
    }
}
