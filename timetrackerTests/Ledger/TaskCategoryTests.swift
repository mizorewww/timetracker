import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskCategoryTests {
    @Test
    func categoryFeatureUsesExtensionModelInsteadOfChangingTaskNodeSchema() throws {
        let taskModels = try sourceText("timetracker/Models/TaskModels.swift")
        let taskNodeSource = try #require(
            taskModels.slice(from: "@Model\nfinal class TaskNode", to: "@Model\nfinal class TaskCategory")
        )
        let schemaModels = try sourceText("timetracker/Models/SchemaModels.swift")
        let v3SchemaSource = try #require(
            schemaModels.slice(from: "enum TimeTrackerSchemaV3", to: "enum TimeTrackerSchemaV4")
        )
        let v4SchemaSource = try #require(
            schemaModels.slice(from: "enum TimeTrackerSchemaV4", to: "enum TimeTrackerSchemaV5")
        )
        let v5SchemaSource = try #require(
            schemaModels.slice(from: "enum TimeTrackerSchemaV5", to: "enum TimeTrackerMigrationPlan")
        )

        #expect(taskNodeSource.contains("categoryID") == false)
        #expect(taskModels.contains("final class TaskCategoryAssignment"))
        #expect(v3SchemaSource.contains("TaskCategory") == false)
        #expect(v4SchemaSource.contains("categoryID"))
        #expect(v4SchemaSource.contains("TaskCategoryAssignment.self") == false)
        #expect(v5SchemaSource.contains("TaskCategoryAssignment.self"))
    }

    @Test @MainActor
    func legacyV4CategoryStoreMigratesToCurrentSchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "TimeTrackerLegacyV4-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

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
            title: "Work",
            deviceID: "legacy",
            colorHex: "1677FF",
            iconName: "briefcase",
            includesInForecast: true
        )
        let root = TimeTrackerSchemaV4.TaskNode(
            title: "Legacy Root",
            parentID: nil,
            deviceID: "legacy",
            categoryID: category.id,
            colorHex: nil,
            iconName: nil
        )
        legacyContext.insert(category)
        legacyContext.insert(root)
        try legacyContext.save()

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
        let currentContext = ModelContext(currentContainer)

        #expect(try currentContext.fetch(FetchDescriptor<TaskNode>()).map(\.title) == ["Legacy Root"])
        #expect(try currentContext.fetch(FetchDescriptor<TaskCategory>()).map(\.title) == ["Work"])
        #expect(try currentContext.fetch(FetchDescriptor<TaskCategoryAssignment>()).map(\.categoryID) == [category.id])
    }

    @Test @MainActor
    func rootTasksOwnCategoryAndChildrenInheritThroughReadModel() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let category = try repository.createCategory(
            title: "Work",
            colorHex: "1677FF",
            iconName: "briefcase",
            includesInForecast: true
        )
        let root = try repository.createTask(
            title: "Client Project",
            parentID: nil,
            categoryID: category.id,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(title: "Research", parentID: root.id, colorHex: nil, iconName: nil)

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        #expect(try repository.categoryID(forRootTaskID: root.id) == category.id)
        #expect(try repository.categoryID(forRootTaskID: child.id) == nil)
        #expect(store.effectiveCategory(for: child)?.id == category.id)
        #expect(store.taskTreeSections(expandedTaskIDs: [root.id]).map(\.title) == ["Work"])
    }

    @Test @MainActor
    func categoriesCanDisableForecastForTheirWholeRootTree() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let category = try taskRepository.createCategory(
            title: "Health",
            colorHex: "34C759",
            iconName: "heart",
            includesInForecast: false
        )
        let root = try taskRepository.createTask(
            title: "Fitness",
            parentID: nil,
            categoryID: category.id,
            colorHex: nil,
            iconName: nil
        )
        let child = try taskRepository.createTask(title: "Morning routine", parentID: root.id, colorHex: nil, iconName: nil)
        let end = Date().addingTimeInterval(-60)
        _ = try timeRepository.addManualSegment(
            taskID: child.id,
            startedAt: end.addingTimeInterval(-1_800),
            endedAt: end,
            note: nil
        )
        context.insert(ChecklistItem(taskID: child.id, title: "Done", isCompleted: true, sortOrder: 10, deviceID: "test"))
        context.insert(ChecklistItem(taskID: child.id, title: "Todo", isCompleted: false, sortOrder: 20, deviceID: "test"))
        try context.save()

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        #expect(store.forecastEligibleTaskIDs().isEmpty)
        #expect(store.rollup(for: child.id)?.forecastState == .disabled)
        #expect(store.rollup(for: root.id)?.forecastState == .disabled)
        #expect(store.forecastDisplayItems().isEmpty)
    }

    @Test @MainActor
    func deletingCategoryKeepsTasksButReturnsThemToUncategorized() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let category = try repository.createCategory(
            title: "Life",
            colorHex: "FF9F0A",
            iconName: "house",
            includesInForecast: false
        )
        let root = try repository.createTask(
            title: "Home",
            parentID: nil,
            categoryID: category.id,
            colorHex: nil,
            iconName: nil
        )

        try repository.softDeleteCategory(categoryID: category.id)
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        let deletedCategory = try repository.category(id: category.id)
        let keptRootOptional = try repository.task(id: root.id)
        let keptRoot = try #require(keptRootOptional)
        #expect(deletedCategory == nil)
        #expect(try repository.categoryID(forRootTaskID: keptRoot.id) == nil)
        #expect(store.taskTreeSections(expandedTaskIDs: []).map(\.title) == [AppStrings.localized("taskCategory.uncategorized")])
    }
}
