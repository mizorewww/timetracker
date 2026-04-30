import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskCategoryTests {
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

        #expect(root.categoryID == category.id)
        #expect(child.categoryID == nil)
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
        #expect(keptRoot.categoryID == nil)
        #expect(store.taskTreeSections(expandedTaskIDs: []).map(\.title) == [AppStrings.localized("taskCategory.uncategorized")])
    }
}
