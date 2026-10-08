import Foundation
import SwiftData
@testable import timetracker

/// Seeds a legacy-schema store and reopens it through the current schema so
/// every migration fixture shares one container/autoreleasepool scaffold.
@MainActor
struct LegacyStoreFixture<Seed> {
    let name: String
    let directory: URL
    let storeURL: URL
    let seed: Seed

    static func create<LegacySchema: VersionedSchema>(
        name: String,
        schema _: LegacySchema.Type,
        directoryPrefix: String? = nil,
        seed: (ModelContext) throws -> Seed
    ) throws -> LegacyStoreFixture<Seed> {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "TimeTracker\(directoryPrefix ?? name)-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storeURL = directory.appending(path: "store.sqlite")
        let seeded = try autoreleasepool {
            let legacySchema = Schema(versionedSchema: LegacySchema.self)
            let configuration = ModelConfiguration(
                name,
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
            let seed = try seed(context)
            try context.save()
            return seed
        }

        return LegacyStoreFixture(
            name: name,
            directory: directory,
            storeURL: storeURL,
            seed: seeded
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try autoreleasepool {
            let currentSchema = TimeTrackerModelRegistry.currentSchema
            let configuration = ModelConfiguration(
                name,
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

@MainActor
struct LegacyV4CategoryStoreFixture {
    let fixture: LegacyStoreFixture<(rootTaskID: UUID, categoryID: UUID)>

    var storeURL: URL {
        fixture.storeURL
    }

    var rootTaskID: UUID {
        fixture.seed.rootTaskID
    }

    var categoryID: UUID {
        fixture.seed.categoryID
    }

    static func create(
        rootTitle: String = "Legacy Root",
        categoryTitle: String = "Work",
        deviceID: String = "legacy"
    ) throws -> LegacyV4CategoryStoreFixture {
        try LegacyV4CategoryStoreFixture(
            fixture: LegacyStoreFixture.create(
                name: "LegacyV4",
                schema: TimeTrackerSchemaV4.self
            ) { context in
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
                context.insert(category)
                context.insert(root)
                return (root.id, category.id)
            }
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try fixture.withCurrentContext(body)
    }

    func remove() {
        fixture.remove()
    }
}

@MainActor
struct LegacyV8DailySummaryStoreFixture {
    let fixture: LegacyStoreFixture<UUID>

    var storeURL: URL {
        fixture.storeURL
    }

    var taskID: UUID {
        fixture.seed
    }

    static func create() throws -> LegacyV8DailySummaryStoreFixture {
        try LegacyV8DailySummaryStoreFixture(
            fixture: LegacyStoreFixture.create(
                name: "LegacyV8",
                schema: TimeTrackerSchemaV8.self
            ) { context in
                let task = TaskNode(title: "V8 task", parentID: nil, deviceID: "legacy")
                let summary = DailySummary(
                    date: Date(timeIntervalSinceReferenceDate: 100_000),
                    taskID: task.id,
                    grossSeconds: 900,
                    wallClockSeconds: 900,
                    pomodoroCount: 1,
                    interruptionCount: 0
                )
                context.insert(task)
                context.insert(summary)
                return task.id
            }
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try fixture.withCurrentContext(body)
    }

    func remove() {
        fixture.remove()
    }
}

@MainActor
struct LegacyV9InboxStoreFixture {
    let fixture: LegacyStoreFixture<(dismissedItemID: UUID, readyItemID: UUID, suggestionID: UUID)>

    var storeURL: URL {
        fixture.storeURL
    }

    var dismissedItemID: UUID {
        fixture.seed.dismissedItemID
    }

    var readyItemID: UUID {
        fixture.seed.readyItemID
    }

    var suggestionID: UUID {
        fixture.seed.suggestionID
    }

    static func create() throws -> LegacyV9InboxStoreFixture {
        try LegacyV9InboxStoreFixture(
            fixture: LegacyStoreFixture.create(
                name: "LegacyV9",
                schema: TimeTrackerSchemaV9.self
            ) { context in
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

                context.insert(task)
                context.insert(dismissedItem)
                context.insert(readyItem)
                context.insert(suggestion)
                return (
                    dismissedItemID: dismissedItem.id,
                    readyItemID: readyItem.id,
                    suggestionID: suggestion.id
                )
            }
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try fixture.withCurrentContext(body)
    }

    func remove() {
        fixture.remove()
    }
}
