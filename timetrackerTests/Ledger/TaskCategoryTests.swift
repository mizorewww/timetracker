import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskCategoryTests {
    @Test
    func categoryFeatureUsesExtensionModelInsteadOfChangingTaskNodeSchema() throws {
        let currentTaskProperties = Set(Mirror(reflecting: TaskNode(title: "Current", parentID: nil, deviceID: "test")).children.compactMap(\.label))

        #expect(currentTaskProperties.contains("categoryID") == false)
        #expect(TimeTrackerSchemaV3.models.contains { $0 == TaskCategory.self } == false)
        #expect(TimeTrackerSchemaV4.models.contains { $0 == TimeTrackerSchemaV4.TaskCategory.self })
        #expect(TimeTrackerSchemaV4.models.contains { $0 == TaskCategoryAssignment.self } == false)
        #expect(TimeTrackerSchemaV5.models.contains { $0 == TaskCategoryAssignment.self })
    }

    @Test @MainActor
    func legacyV4CategoryStoreMigratesToCurrentSchema() throws {
        let fixture = try LegacyV4CategoryStoreFixture.create()
        defer { fixture.remove() }
        let currentContext = try fixture.makeCurrentContext()

        #expect(try currentContext.fetch(FetchDescriptor<TaskNode>()).map(\.title) == ["Legacy Root"])
        #expect(try currentContext.fetch(FetchDescriptor<TaskCategory>()).map(\.title) == ["Work"])
        #expect(try currentContext.fetch(FetchDescriptor<TaskCategoryAssignment>()).map(\.categoryID) == [fixture.categoryID])
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
    func taskTreeShowsEmptyCategories() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let category = try repository.createCategory(
            title: "Learning",
            colorHex: "5856D6",
            iconName: "book",
            includesInForecast: true
        )

        let sections = TaskTreeService().categorySections(
            rootTasks: [],
            categories: [category],
            categoryIDByRootTaskID: [:]
        )
        #expect(sections.map(\.title) == ["Learning"])
        #expect(sections.first?.categoryID == category.id)
        #expect(sections.first?.rootTasks.isEmpty == true)
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

    @Test @MainActor
    func rootTaskCategoryCanBeChangedThroughTaskEditorWithoutChangingHierarchy() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let work = try repository.createCategory(
            title: "Work",
            colorHex: "1677FF",
            iconName: "briefcase",
            includesInForecast: true
        )
        let life = try repository.createCategory(
            title: "Life",
            colorHex: "FF9F0A",
            iconName: "house",
            includesInForecast: false
        )
        let root = try repository.createTask(
            title: "Client Project",
            parentID: nil,
            categoryID: work.id,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Research",
            parentID: root.id,
            categoryID: nil,
            colorHex: nil,
            iconName: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        var draft = TaskEditorDraft(task: root, categoryID: work.id, checklistItems: [])
        draft.categoryID = life.id
        #expect(store.saveTaskDraft(draft))

        #expect(try repository.categoryID(forRootTaskID: root.id) == life.id)
        #expect(try repository.task(id: child.id)?.parentID == root.id)
        #expect(store.effectiveCategory(for: child)?.id == life.id)
        #expect(try repository.categoryID(forRootTaskID: child.id) == nil)
    }

    @Test @MainActor
    func categoryAssignmentMutationCollapsesConcurrentActiveAssignments() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "local-device")
        let firstCategory = try repository.createCategory(
            title: "First",
            colorHex: nil,
            iconName: nil,
            includesInForecast: true
        )
        let secondCategory = try repository.createCategory(
            title: "Second",
            colorHex: nil,
            iconName: nil,
            includesInForecast: true
        )
        let root = try repository.createTask(
            title: "Concurrent root",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let older = TaskCategoryAssignment(
            taskID: root.id,
            categoryID: firstCategory.id,
            deviceID: "remote-a"
        )
        older.updatedAt = Date().addingTimeInterval(-60)
        let newer = TaskCategoryAssignment(
            taskID: root.id,
            categoryID: secondCategory.id,
            deviceID: "remote-b"
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        try repository.setCategoryAssignment(categoryID: firstCategory.id, forRootTaskID: root.id)
        try context.save()
        var assignments = try context.fetch(FetchDescriptor<TaskCategoryAssignment>())
            .filter { $0.taskID == root.id }
        #expect(assignments.filter { $0.deletedAt == nil }.count == 1)
        #expect(assignments.first { $0.deletedAt == nil }?.categoryID == firstCategory.id)
        #expect(assignments.filter { $0.deletedAt != nil }.count == 1)

        try repository.setCategoryAssignment(categoryID: nil, forRootTaskID: root.id)
        try context.save()
        assignments = try context.fetch(FetchDescriptor<TaskCategoryAssignment>())
            .filter { $0.taskID == root.id }
        #expect(assignments.allSatisfy { $0.deletedAt != nil })
        #expect(try repository.categoryID(forRootTaskID: root.id) == nil)
    }

    @Test @MainActor
    func equalTimestampCategoryAssignmentsUseOneWinnerAcrossRepositoryStoreAndAnalytics() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "local-device")
        let losingCategory = try repository.createCategory(
            title: "Losing category",
            colorHex: nil,
            iconName: nil,
            includesInForecast: true
        )
        let winningCategory = try repository.createCategory(
            title: "Winning category",
            colorHex: nil,
            iconName: nil,
            includesInForecast: true
        )
        let root = try repository.createTask(
            title: "Concurrent root",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let timestamp = Date().addingTimeInterval(-60)
        let losingAssignment = TaskCategoryAssignment(
            taskID: root.id,
            categoryID: losingCategory.id,
            deviceID: "device-a"
        )
        losingAssignment.createdAt = timestamp
        losingAssignment.updatedAt = timestamp
        let winningAssignment = TaskCategoryAssignment(
            taskID: root.id,
            categoryID: winningCategory.id,
            deviceID: "device-z"
        )
        winningAssignment.createdAt = timestamp
        winningAssignment.updatedAt = timestamp
        context.insert(winningAssignment)
        context.insert(losingAssignment)
        try context.save()

        #expect(
            [losingAssignment, winningAssignment]
                .logicalWinnersByTaskID()[root.id]?.id == winningAssignment.id
        )
        #expect(
            [winningAssignment, losingAssignment]
                .logicalWinnersByTaskID()[root.id]?.id == winningAssignment.id
        )
        #expect(try repository.categoryID(forRootTaskID: root.id) == winningCategory.id)

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        #expect(store.effectiveCategory(for: root)?.id == winningCategory.id)

        let now = Date()
        let segment = TimeSegment(
            sessionID: UUID(),
            taskID: root.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-30),
            endedAt: now
        )
        let breakdown = AnalyticsStore().categoryBreakdown(
            segments: [segment],
            tasks: [root],
            taskCategories: [losingCategory, winningCategory],
            taskCategoryAssignments: [winningAssignment, losingAssignment],
            range: .today,
            now: now,
            calendar: .current
        )
        #expect(breakdown.first?.title == winningCategory.title)
    }
}
