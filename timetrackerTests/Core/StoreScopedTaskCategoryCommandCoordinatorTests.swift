import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedTaskCategoryCommandCoordinatorTests {
    @Test
    func staleDraftCannotOverwriteANewerCategoryEdit() throws {
        let context = try makeTestContext()
        let category = try makeCategory(in: context, title: "Original")
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let visibleCategory = try #require(store.taskCategory(for: category.id))
        var staleDraft = TaskCategoryEditorDraft(category: visibleCategory)
        var siblingDraft = TaskCategoryEditorDraft(category: visibleCategory)
        siblingDraft.title = "Sibling winner"
        _ = try coordinator(
            container: context.container,
            deviceID: "sibling"
        ).save(draft: siblingDraft)
        staleDraft.title = "Stale overwrite"

        #expect(store.saveTaskCategoryDraft(staleDraft) == false)
        #expect(store.errorMessage == AppStrings.localized("taskCategory.error.changed"))
        let persisted = try #require(
            try freshRepository(context.container).category(id: category.id)
        )
        #expect(persisted.title == "Sibling winner")
        #expect(persisted.deviceID == "sibling")
        #expect(store.taskCategory(for: category.id)?.title == "Sibling winner")
    }

    @Test
    func staleDraftCannotResurrectADeletedCategory() throws {
        let context = try makeTestContext()
        let category = try makeCategory(in: context, title: "Delete elsewhere")
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var staleDraft = TaskCategoryEditorDraft(
            category: try #require(store.taskCategory(for: category.id))
        )
        staleDraft.title = "Must not return"
        _ = try coordinator(
            container: context.container,
            deviceID: "sibling"
        ).delete(baseline: TaskCategoryMutationBaseline(category: category))

        #expect(store.saveTaskCategoryDraft(staleDraft) == false)
        #expect(store.errorMessage == AppStrings.localized("taskCategory.error.unavailable"))
        #expect(try freshRepository(context.container).category(id: category.id) == nil)
        #expect(store.taskCategory(for: category.id) == nil)
        #expect(store.deleteTaskCategory(baseline: try #require(staleDraft.baseline)) == false)
        #expect(store.errorMessage == AppStrings.localized("taskCategory.error.unavailable"))
    }

    @Test
    func staleDeleteCannotRemoveANewerCategoryEdit() throws {
        let context = try makeTestContext()
        let category = try makeCategory(in: context, title: "Keep winner")
        let staleBaseline = TaskCategoryMutationBaseline(category: category)
        var siblingDraft = TaskCategoryEditorDraft(category: category)
        siblingDraft.title = "Edited winner"
        let coordinator = coordinator(container: context.container, deviceID: "sibling")
        _ = try coordinator.save(draft: siblingDraft)

        #expect(throws: StoreScopedTaskCategoryMutationError.categoryChanged) {
            try coordinator.delete(baseline: staleBaseline)
        }
        let persisted = try #require(
            try freshRepository(context.container).category(id: category.id)
        )
        #expect(persisted.title == "Edited winner")
    }

    @Test
    func deleteAfterAssignmentTombstonesTheCanonicalAssignment() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "seed")
        let category = try repository.createCategory(
            title: "Assigned",
            includesInForecast: true
        )
        let task = try repository.createTask(
            title: "Root",
            parentID: nil,
            categoryID: category.id,
            colorHex: nil,
            iconName: nil
        )

        _ = try coordinator(
            container: context.container,
            deviceID: "delete"
        ).delete(baseline: TaskCategoryMutationBaseline(category: category))

        let freshContext = ModelContext(context.container)
        let assignments = try freshContext.fetch(FetchDescriptor<TaskCategoryAssignment>())
        #expect(assignments.contains(where: { $0.taskID == task.id }))
        #expect(assignments.filter { $0.taskID == task.id }.allSatisfy { $0.deletedAt != nil })
        #expect(try freshRepository(context.container).categoryID(forRootTaskID: task.id) == nil)
    }

    @Test
    func assignmentAfterCategoryDeleteIsRejectedWithoutAnOrphan() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "seed")
        let category = try repository.createCategory(
            title: "Soon deleted",
            includesInForecast: true
        )
        let task = try repository.createTask(
            title: "Unassigned root",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var staleTaskDraft = store.editorDraft(for: try #require(store.task(for: task.id)))
        staleTaskDraft.categoryID = category.id
        _ = try coordinator(
            container: context.container,
            deviceID: "delete"
        ).delete(baseline: TaskCategoryMutationBaseline(category: category))

        #expect(throws: TaskLifecycleMutationError.staleDraft) {
            try StoreScopedTaskLifecycleCommandCoordinator(
                container: context.container,
                writeAuthorization: .isolatedTestHarness,
                deviceID: "assignment"
            ).save(draft: staleTaskDraft, sanitizedTitle: staleTaskDraft.title)
        }
        #expect(try freshRepository(context.container).categoryID(forRootTaskID: task.id) == nil)
    }

    @Test
    func consecutiveSceneCreatesUseFreshCanonicalOrdering() throws {
        let context = try makeTestContext()
        var firstDraft = TaskCategoryEditorDraft()
        firstDraft.title = "First"
        var secondDraft = TaskCategoryEditorDraft()
        secondDraft.title = "Second"

        _ = try coordinator(container: context.container, deviceID: "first")
            .save(draft: firstDraft)
        _ = try coordinator(container: context.container, deviceID: "second")
            .save(draft: secondDraft)

        let categories = try freshRepository(context.container).categories()
        #expect(categories.map(\.title) == ["First", "Second"])
        #expect(Set(categories.map(\.sortOrder)).count == 2)
        #expect(categories[1].sortOrder > categories[0].sortOrder)
    }

    @Test
    func repositoryDoesNotReportMissingCategoryMutationsAsSuccess() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let missingID = UUID()

        #expect(throws: TaskRepositoryError.categoryUnavailable) {
            try repository.updateCategory(
                categoryID: missingID,
                title: "Missing",
                colorHex: nil,
                iconName: nil,
                includesInForecast: true
            )
        }
        #expect(throws: TaskRepositoryError.categoryUnavailable) {
            try repository.softDeleteCategory(categoryID: missingID)
        }
    }

    private func makeCategory(
        in context: ModelContext,
        title: String
    ) throws -> TaskCategory {
        try SwiftDataTaskRepository(context: context, deviceID: "seed")
            .createCategory(title: title, includesInForecast: true)
    }

    private func coordinator(
        container: ModelContainer,
        deviceID: String
    ) -> StoreScopedTaskCategoryCommandCoordinator {
        StoreScopedTaskCategoryCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: deviceID
        )
    }

    private func freshRepository(_ container: ModelContainer) -> SwiftDataTaskRepository {
        SwiftDataTaskRepository(
            context: ModelContext(container),
            deviceID: "fresh"
        )
    }
}
