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
    func reorderPersistsCanonicalOrderWithOneDominatingRevision() throws {
        let context = try makeTestContext()
        let categories = try makeCategories(
            ["First", "Second", "Third"],
            in: context
        )
        let baseline = TaskCategoryOrderMutationBaseline(categories: categories)
        let mutationIDsBefore = baseline.categoryMutationIDs
        let latestObservedDate = try #require(categories.map(\.updatedAt).max())
        let requestedOrder = [categories[2].id, categories[0].id, categories[1].id]

        let outcome = try coordinator(
            container: context.container,
            deviceID: "reorder",
            nowProvider: { .distantPast }
        ).reorder(
            orderedCategoryIDs: requestedOrder,
            baseline: baseline
        )

        #expect(outcome.didMutate)
        #expect(outcome.affectedCategoryIDs == Set(requestedOrder))
        #expect(
            outcome.events ==
                [.taskChanged(taskID: nil, affectedAncestorIDs: [])]
        )
        let persisted = try freshRepository(context.container).categories()
        #expect(persisted.map(\.id) == requestedOrder)
        #expect(persisted.map(\.sortOrder) == [10, 20, 30])
        #expect(persisted.allSatisfy { $0.updatedAt > latestObservedDate })
        #expect(Set(persisted.map(\.updatedAt)).count == 1)
        #expect(persisted.allSatisfy { $0.deviceID == "reorder" })
        let persistedBatchMutationIDs = Set(
            persisted.map(\.clientMutationID)
        )
        #expect(persistedBatchMutationIDs.count == 1)
        #expect(
            persisted.allSatisfy {
                $0.clientMutationID != mutationIDsBefore[$0.id]
            }
        )
    }

    @Test
    func sameOrderIsANoOpThatPreservesEveryRevision() throws {
        let context = try makeTestContext()
        let categories = try makeCategories(
            ["First", "Second", "Third"],
            in: context
        )
        let baseline = TaskCategoryOrderMutationBaseline(categories: categories)
        let sortOrderBefore = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, $0.sortOrder) }
        )
        let updatedAtBefore = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, $0.updatedAt) }
        )
        let deviceIDBefore = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.id, $0.deviceID) }
        )

        let outcome = try coordinator(
            container: context.container,
            deviceID: "must-not-write",
            nowProvider: { .distantFuture }
        ).reorder(
            orderedCategoryIDs: baseline.orderedCategoryIDs,
            baseline: baseline
        )

        #expect(outcome.didMutate == false)
        #expect(outcome.events.isEmpty)
        let persisted = try freshRepository(context.container).categories()
        #expect(persisted.map(\.id) == baseline.orderedCategoryIDs)
        #expect(
            persisted.allSatisfy {
                $0.sortOrder == sortOrderBefore[$0.id] &&
                    $0.updatedAt == updatedAtBefore[$0.id] &&
                    $0.deviceID == deviceIDBefore[$0.id] &&
                    $0.clientMutationID == baseline.categoryMutationIDs[$0.id]
            }
        )
    }

    @Test
    func staleBaselineCannotOverwriteASiblingReorder() throws {
        let context = try makeTestContext()
        let categories = try makeCategories(
            ["First", "Second", "Third"],
            in: context
        )
        let staleBaseline = TaskCategoryOrderMutationBaseline(
            categories: categories
        )
        let siblingOrder = [
            categories[1].id,
            categories[2].id,
            categories[0].id
        ]
        _ = try coordinator(
            container: context.container,
            deviceID: "sibling"
        ).reorder(
            orderedCategoryIDs: siblingOrder,
            baseline: staleBaseline
        )

        #expect(throws: StoreScopedTaskCategoryMutationError.categoryChanged) {
            try coordinator(
                container: context.container,
                deviceID: "stale"
            ).reorder(
                orderedCategoryIDs: [
                    categories[2].id,
                    categories[0].id,
                    categories[1].id
                ],
                baseline: staleBaseline
            )
        }
        #expect(
            try freshRepository(context.container).categories().map(\.id) ==
                siblingOrder
        )
    }

    @Test
    func facadeRejectsAStaleEditAndRefreshesTheWinningCategory() throws {
        let context = try makeTestContext()
        _ = try makeCategories(["First", "Second", "Third"], in: context)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let visibleCategories = store.taskCategories
        let sheetBaseline = TaskCategoryOrderMutationBaseline(
            categories: visibleCategories
        )
        var siblingDraft = TaskCategoryEditorDraft(
            category: visibleCategories[0]
        )
        siblingDraft.title = "Sibling winner"
        _ = try coordinator(
            container: context.container,
            deviceID: "sibling"
        ).save(draft: siblingDraft)
        try store.refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
        #expect(
            store.taskCategory(for: visibleCategories[0].id)?.title ==
                "Sibling winner"
        )
        let requestedOrder = [
            visibleCategories[2].id,
            visibleCategories[0].id,
            visibleCategories[1].id
        ]

        #expect(
            store.reorderTaskCategories(
                orderedCategoryIDs: requestedOrder,
                baseline: sheetBaseline
            ) == false
        )

        #expect(
            store.errorMessage ==
                AppStrings.localized("taskCategory.error.changed")
        )
        #expect(
            store.taskCategory(for: visibleCategories[0].id)?.title ==
                "Sibling winner"
        )
        #expect(
            store.taskCategories.map(\.id) ==
                visibleCategories.map(\.id)
        )
    }

    @Test
    func facadeRefreshesItsCategoryOrderAfterASuccessfulReorder() throws {
        let context = try makeTestContext()
        _ = try makeCategories(["First", "Second", "Third"], in: context)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let requestedOrder = [
            store.taskCategories[2].id,
            store.taskCategories[0].id,
            store.taskCategories[1].id
        ]

        #expect(
            store.reorderTaskCategories(
                orderedCategoryIDs: requestedOrder
            )
        )
        #expect(store.taskCategories.map(\.id) == requestedOrder)
        #expect(
            try freshRepository(context.container).categories().map(\.id) ==
                requestedOrder
        )
    }

    @Test
    func staleMembershipCannotOverwriteACreateOrDelete() throws {
        let context = try makeTestContext()
        let original = try makeCategories(["First", "Second"], in: context)
        let baselineBeforeCreate = TaskCategoryOrderMutationBaseline(
            categories: original
        )
        var createDraft = TaskCategoryEditorDraft()
        createDraft.title = "Third"
        let created = try coordinator(
            container: context.container,
            deviceID: "sibling-create"
        ).save(draft: createDraft)

        #expect(throws: StoreScopedTaskCategoryMutationError.categoryChanged) {
            try coordinator(
                container: context.container,
                deviceID: "stale"
            ).reorder(
                orderedCategoryIDs: original.reversed().map(\.id),
                baseline: baselineBeforeCreate
            )
        }

        let beforeDelete = try freshRepository(context.container).categories()
        let baselineBeforeDelete = TaskCategoryOrderMutationBaseline(
            categories: beforeDelete
        )
        let deletedCategory = try #require(
            beforeDelete.first { $0.id == created.categoryID }
        )
        _ = try coordinator(
            container: context.container,
            deviceID: "sibling-delete"
        ).delete(
            baseline: TaskCategoryMutationBaseline(
                category: deletedCategory
            )
        )

        #expect(throws: StoreScopedTaskCategoryMutationError.categoryChanged) {
            try coordinator(
                container: context.container,
                deviceID: "stale"
            ).reorder(
                orderedCategoryIDs: beforeDelete.reversed().map(\.id),
                baseline: baselineBeforeDelete
            )
        }
        #expect(
            try freshRepository(context.container).categories().map(\.id) ==
                original.map(\.id)
        )
    }

    @Test
    func directSortOrderMutationInvalidatesTheFullOrderBaseline() throws {
        let context = try makeTestContext()
        let categories = try makeCategories(
            ["First", "Second", "Third"],
            in: context
        )
        let baseline = TaskCategoryOrderMutationBaseline(categories: categories)
        let directContext = ModelContext(context.container)
        let directRepository = SwiftDataTaskRepository(
            context: directContext,
            deviceID: "direct"
        )
        let directlyMoved = try #require(
            try directRepository.category(id: categories[0].id)
        )
        directlyMoved.sortOrder = 40
        try directContext.save()

        #expect(
            directlyMoved.clientMutationID ==
                baseline.categoryMutationIDs[directlyMoved.id]
        )
        #expect(throws: StoreScopedTaskCategoryMutationError.categoryChanged) {
            try coordinator(
                container: context.container,
                deviceID: "stale"
            ).reorder(
                orderedCategoryIDs: [
                    categories[2].id,
                    categories[0].id,
                    categories[1].id
                ],
                baseline: baseline
            )
        }
        #expect(
            try freshRepository(context.container).categories().map(\.id) ==
                [categories[1].id, categories[2].id, categories[0].id]
        )
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

    private func makeCategories(
        _ titles: [String],
        in context: ModelContext
    ) throws -> [TaskCategory] {
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        )
        return try titles.map {
            try repository.createCategory(
                title: $0,
                includesInForecast: true
            )
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
        deviceID: String,
        nowProvider: @escaping () -> Date = Date.init
    ) -> StoreScopedTaskCategoryCommandCoordinator {
        StoreScopedTaskCategoryCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: deviceID,
            nowProvider: nowProvider
        )
    }

    private func freshRepository(_ container: ModelContainer) -> SwiftDataTaskRepository {
        SwiftDataTaskRepository(
            context: ModelContext(container),
            deviceID: "fresh"
        )
    }
}
