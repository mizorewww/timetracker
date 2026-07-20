import Foundation
import SwiftData
@testable import timetracker

@MainActor
struct LegacyV12TaskPlanningStoreFixture {
    let directory: URL
    let storeURL: URL
    let taskID: UUID

    static func create() throws -> LegacyV12TaskPlanningStoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "TimeTrackerLegacyV12-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let storeURL = directory.appending(path: "store.sqlite")
        let taskID = try autoreleasepool {
            let legacySchema = Schema(versionedSchema: TimeTrackerSchemaV12.self)
            let configuration = ModelConfiguration(
                "LegacyV12TaskPlanning",
                schema: legacySchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: legacySchema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [configuration]
            )
            let context = ModelContext(container)
            let task = TaskNode(
                title: "V12 preserved task",
                parentID: nil,
                deviceID: "legacy"
            )
            context.insert(task)
            try context.save()
            return task.id
        }

        return LegacyV12TaskPlanningStoreFixture(
            directory: directory,
            storeURL: storeURL,
            taskID: taskID
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try autoreleasepool {
            let currentSchema = TimeTrackerModelRegistry.currentSchema
            let configuration = ModelConfiguration(
                "LegacyV12TaskPlanning",
                schema: currentSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: currentSchema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [configuration]
            )
            return try body(ModelContext(container))
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
