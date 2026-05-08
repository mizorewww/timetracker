import Foundation
import SwiftData
@testable import timetracker

@MainActor
struct LegacyV4CategoryStoreFixture {
    let directory: URL
    let storeURL: URL
    let rootTaskID: UUID
    let categoryID: UUID

    static func create(
        rootTitle: String = "Legacy Root",
        categoryTitle: String = "Work",
        deviceID: String = "legacy"
    ) throws -> LegacyV4CategoryStoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TimeTrackerLegacyV4-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storeURL = directory.appending(path: "store.sqlite")
        let legacySchema = Schema(versionedSchema: TimeTrackerSchemaV4.self)
        let legacyConfiguration = ModelConfiguration(
            "LegacyV4",
            schema: legacySchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let legacyContainer = try ModelContainer(
            for: legacySchema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [legacyConfiguration]
        )
        let legacyContext = ModelContext(legacyContainer)
        let category = TimeTrackerSchemaV4.TaskCategory(
            title: categoryTitle,
            deviceID: deviceID,
            colorHex: "1677FF",
            iconName: "briefcase",
            includesInForecast: true
        )
        let root = TimeTrackerSchemaV4.TaskNode(
            title: rootTitle,
            parentID: nil,
            deviceID: deviceID,
            categoryID: category.id,
            colorHex: nil,
            iconName: nil
        )
        legacyContext.insert(category)
        legacyContext.insert(root)
        try legacyContext.save()

        return LegacyV4CategoryStoreFixture(
            directory: directory,
            storeURL: storeURL,
            rootTaskID: root.id,
            categoryID: category.id
        )
    }

    func makeCurrentContext() throws -> ModelContext {
        let currentSchema = TimeTrackerModelRegistry.currentSchema
        let currentConfiguration = ModelConfiguration(
            "LegacyV4",
            schema: currentSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let currentContainer = try ModelContainer(
            for: currentSchema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [currentConfiguration]
        )
        return ModelContext(currentContainer)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
