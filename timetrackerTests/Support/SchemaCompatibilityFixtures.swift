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
        let ids = try autoreleasepool {
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
            return (root.id, category.id)
        }

        return LegacyV4CategoryStoreFixture(
            directory: directory,
            storeURL: storeURL,
            rootTaskID: ids.0,
            categoryID: ids.1
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try autoreleasepool {
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
            return try body(ModelContext(currentContainer))
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
struct LegacyV8DailySummaryStoreFixture {
    let storeURL: URL
    let taskID: UUID

    static func create() throws -> LegacyV8DailySummaryStoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TimeTrackerLegacyV8-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storeURL = directory.appending(path: "store.sqlite")
        let taskID = try autoreleasepool {
            let legacySchema = Schema(versionedSchema: TimeTrackerSchemaV8.self)
            let legacyConfiguration = ModelConfiguration(
                "LegacyV8",
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
            let task = TaskNode(title: "V8 task", parentID: nil, deviceID: "legacy")
            let summary = DailySummary(
                date: Date(timeIntervalSinceReferenceDate: 100_000),
                taskID: task.id,
                grossSeconds: 900,
                wallClockSeconds: 900,
                pomodoroCount: 1,
                interruptionCount: 0
            )
            legacyContext.insert(task)
            legacyContext.insert(summary)
            try legacyContext.save()
            return task.id
        }

        return LegacyV8DailySummaryStoreFixture(
            storeURL: storeURL,
            taskID: taskID
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try autoreleasepool {
            let currentSchema = TimeTrackerModelRegistry.currentSchema
            let currentConfiguration = ModelConfiguration(
                "LegacyV8",
                schema: currentSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let currentContainer = try ModelContainer(
                for: currentSchema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [currentConfiguration]
            )
            return try body(ModelContext(currentContainer))
        }
    }
}

@MainActor
struct LegacyV9InboxStoreFixture {
    let storeURL: URL
    let dismissedItemID: UUID
    let readyItemID: UUID
    let suggestionID: UUID

    static func create() throws -> LegacyV9InboxStoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TimeTrackerLegacyV9-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storeURL = directory.appending(path: "store.sqlite")
        let ids = try autoreleasepool {
            let legacySchema = Schema(versionedSchema: TimeTrackerSchemaV9.self)
            let legacyConfiguration = ModelConfiguration(
                "LegacyV9",
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
            let task = TaskNode(title: "Migration target", parentID: nil, deviceID: "legacy")
            let dismissedItem = TimeTrackerSchemaV9.InboxItem(
                title: "Dismissed before migration",
                deviceID: "legacy"
            )
            dismissedItem.suggestionGeneratedAt = Date(timeIntervalSinceReferenceDate: 100)
            let readyItem = TimeTrackerSchemaV9.InboxItem(
                title: "Suggestion survives migration",
                deviceID: "legacy"
            )
            readyItem.suggestedTaskID = task.id
            readyItem.suggestionGeneratedAt = Date(timeIntervalSinceReferenceDate: 200)
            let suggestion = TimeTrackerSchemaV9.InboxSuggestion(
                inboxItemID: readyItem.id,
                taskID: task.id,
                titleSnapshot: readyItem.title,
                deviceID: "legacy"
            )

            legacyContext.insert(task)
            legacyContext.insert(dismissedItem)
            legacyContext.insert(readyItem)
            legacyContext.insert(suggestion)
            try legacyContext.save()
            return (dismissedItem.id, readyItem.id, suggestion.id)
        }

        return LegacyV9InboxStoreFixture(
            storeURL: storeURL,
            dismissedItemID: ids.0,
            readyItemID: ids.1,
            suggestionID: ids.2
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try autoreleasepool {
            let currentSchema = TimeTrackerModelRegistry.currentSchema
            let currentConfiguration = ModelConfiguration(
                "LegacyV9",
                schema: currentSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let currentContainer = try ModelContainer(
                for: currentSchema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [currentConfiguration]
            )
            return try body(ModelContext(currentContainer))
        }
    }
}
