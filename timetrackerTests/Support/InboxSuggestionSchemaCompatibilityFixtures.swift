import Foundation
import SwiftData
@testable import timetracker

@MainActor
struct LegacyV11InboxSuggestionStoreFixture {
    let storeURL: URL
    let inboxItemID: UUID
    let suggestionID: UUID
    let taskID: UUID

    static func create() throws -> LegacyV11InboxSuggestionStoreFixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TimeTrackerLegacyV11-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storeURL = directory.appending(path: "store.sqlite")
        let ids = try autoreleasepool {
            let legacySchema = Schema(versionedSchema: TimeTrackerSchemaV11.self)
            let configuration = ModelConfiguration(
                "LegacyV11",
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
            let task = TaskNode(title: "Legacy destination", parentID: nil, deviceID: "legacy")
            let item = InboxItem(title: "Legacy suggestion", deviceID: "legacy")
            let suggestion = TimeTrackerSchemaV11.InboxSuggestion(
                inboxItemID: item.id,
                inboxItemContextID: item.effectiveSuggestionContextID,
                inboxItemRevisionID: item.effectiveSuggestionRevisionID,
                taskID: task.id,
                reason: "V11 reason",
                iconName: "archivebox",
                colorHex: "FF9500",
                modelID: "legacy-model",
                titleSnapshot: item.title,
                generatedAt: Date(timeIntervalSinceReferenceDate: 120_000),
                deviceID: "legacy"
            )
            context.insert(task)
            context.insert(item)
            context.insert(suggestion)
            try context.save()
            return (item.id, suggestion.id, task.id)
        }

        return LegacyV11InboxSuggestionStoreFixture(
            storeURL: storeURL,
            inboxItemID: ids.0,
            suggestionID: ids.1,
            taskID: ids.2
        )
    }

    func withCurrentContext<Result>(
        _ body: (ModelContext) throws -> Result
    ) throws -> Result {
        try autoreleasepool {
            let currentSchema = TimeTrackerModelRegistry.currentSchema
            let configuration = ModelConfiguration(
                "LegacyV11",
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
}
