import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedChecklistCommandCoordinatorTests {
    @Test
    func staleSceneCannotOverwriteANewerCompletionMutation() throws {
        let context = try makeTestContext()
        let task = try makeTask(in: context, title: "Checklist owner")
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.addChecklistItem(taskID: task.id, title: "Original"))
        let staleItem = try #require(store.checklistItems(for: task.id).first)

        let sibling = StoreScopedChecklistCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "sibling",
            nowProvider: { Date(timeIntervalSinceReferenceDate: 1_000) }
        )
        _ = try sibling.setCompletion(
            baseline: ChecklistMutationBaseline(item: staleItem),
            isCompleted: true
        )

        #expect(store.toggleChecklistItem(staleItem) == false)
        #expect(store.errorMessage == AppStrings.localized("checklist.error.changed"))
        let winner = try #require(try visibleItems(in: context.container).first)
        #expect(winner.isCompleted)
        #expect(winner.deviceID == "sibling")
        #expect(store.checklistItems(for: task.id).first?.isCompleted == true)
    }

    @Test
    func staleSceneCannotResurrectADeletedChecklistItem() throws {
        let context = try makeTestContext()
        let task = try makeTask(in: context, title: "Checklist owner")
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.addChecklistItem(taskID: task.id, title: "Delete elsewhere"))
        let staleItem = try #require(store.checklistItems(for: task.id).first)

        try ChecklistDraftService().save(
            drafts: [],
            taskID: task.id,
            context: ModelContext(context.container),
            deviceID: "sibling"
        )

        #expect(store.toggleChecklistItem(staleItem) == false)
        #expect(store.errorMessage == AppStrings.localized("checklist.error.unavailable"))
        #expect(store.checklistItems(for: task.id).isEmpty)
        let persisted = try ModelContext(context.container)
            .fetch(FetchDescriptor<ChecklistItem>())
        #expect(persisted.count == 1)
        #expect(persisted.first?.deletedAt != nil)
    }

    @Test
    func siblingTaskDeletionPreventsQuickAddFromCreatingOrphans() throws {
        let context = try makeTestContext()
        let task = try makeTask(in: context, title: "Delete before add")
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        _ = try StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "sibling"
        ).delete(taskID: task.id)

        #expect(store.addChecklistItem(taskID: task.id, title: "Must not orphan") == false)
        #expect(store.errorMessage == AppStrings.localized("systemAction.error.taskNotFound"))
        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)
    }

    @Test
    func consecutiveSceneAddsUseFreshCanonicalOrdering() throws {
        let context = try makeTestContext()
        let task = try makeTask(in: context, title: "Ordered")
        let firstScene = coordinator(container: context.container, deviceID: "first")
        let secondScene = coordinator(container: context.container, deviceID: "second")

        _ = try firstScene.add(taskID: task.id, title: "First")
        _ = try secondScene.add(taskID: task.id, title: "Second")

        let items = try visibleItems(in: context.container)
            .sorted { $0.sortOrder < $1.sortOrder }
        #expect(items.map(\.title) == ["First", "Second"])
        #expect(Set(items.map(\.sortOrder)).count == 2)
        #expect(items[1].sortOrder > items[0].sortOrder)
    }

    @Test
    func mutationOutcomeUsesTheCanonicalParentChain() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "seed")
        let oldParent = try repository.createTask(
            title: "Old parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let newParent = try repository.createTask(
            title: "New parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let child = try repository.createTask(
            title: "Child",
            parentID: oldParent.id,
            colorHex: nil,
            iconName: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = store.editorDraft(for: try #require(store.task(for: child.id)))
        draft.parentID = newParent.id
        _ = try StoreScopedTaskLifecycleCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "sibling"
        ).save(draft: draft, sanitizedTitle: draft.title)

        let outcome = try coordinator(
            container: context.container,
            deviceID: "checklist"
        ).add(taskID: child.id, title: "Fresh hierarchy")

        #expect(outcome.affectedAncestorIDs == [newParent.id])
        #expect(outcome.affectedAncestorIDs.contains(oldParent.id) == false)
    }

    @Test
    func quickAddUsesTheSamePersistenceValidationAsTaskEditorDrafts() throws {
        let context = try makeTestContext()
        let task = try makeTask(in: context, title: "Validated")
        let coordinator = coordinator(container: context.container, deviceID: "test")

        #expect(throws: ChecklistDraftValidationError.controlCharacter(index: 0, field: .title)) {
            try coordinator.add(taskID: task.id, title: "Bad\u{0007}title")
        }
        let oversized = String(
            repeating: "x",
            count: ChecklistDraftPersistencePolicy.maximumTitleByteCount + 1
        )
        #expect(throws: ChecklistDraftValidationError.byteLimitExceeded(
            index: 0,
            field: .title,
            actual: oversized.utf8.count,
            maximum: ChecklistDraftPersistencePolicy.maximumTitleByteCount
        )) {
            try coordinator.add(taskID: task.id, title: oversized)
        }
        #expect(try visibleItems(in: context.container).isEmpty)
    }

    @Test
    func staleReorderCannotOverwriteANewerItemMutation() throws {
        let context = try makeTestContext()
        let task = try makeTask(in: context, title: "Reorder")
        let coordinator = coordinator(container: context.container, deviceID: "test")
        _ = try coordinator.add(taskID: task.id, title: "First")
        _ = try coordinator.add(taskID: task.id, title: "Second")
        let staleItems = try visibleItems(in: context.container)
            .sorted { $0.sortOrder < $1.sortOrder }
        let baseline = ChecklistOrderMutationBaseline(taskID: task.id, items: staleItems)
        _ = try coordinator.setCompletion(
            baseline: ChecklistMutationBaseline(item: staleItems[0]),
            isCompleted: true
        )

        #expect(throws: StoreScopedChecklistMutationError.checklistChanged) {
            try coordinator.reorder(
                baseline: baseline,
                orderedItemIDs: staleItems.reversed().map(\.id)
            )
        }
        let persisted = try visibleItems(in: context.container)
        #expect(persisted.first(where: { $0.id == staleItems[0].id })?.isCompleted == true)
    }

    @Test
    func staleVisualSuggestionCannotOverwriteAManualVisualFromAnotherScene() throws {
        let context = try makeTestContext()
        let task = try makeTask(in: context, title: "Visual owner")
        let writer = coordinator(container: context.container, deviceID: "writer")
        _ = try writer.add(taskID: task.id, title: "Prepare deck")

        let item = try #require(try visibleItems(in: context.container).first)
        let visual = try #require(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<ChecklistItemVisual>())
                .first(where: { $0.checklistItemID == item.id })
        )
        let baseline = ChecklistVisualSuggestionBaseline(
            item: item,
            visual: visual,
            normalizedTitle: ChecklistVisualSuggestionPolicy().normalizedTitle(item.title)
        )

        let siblingContext = ModelContext(context.container)
        let siblingVisual = try #require(
            try siblingContext.fetch(FetchDescriptor<ChecklistItemVisual>())
                .first(where: { $0.id == visual.id })
        )
        siblingVisual.iconName = "paintbrush"
        siblingVisual.colorHex = "EF4444"
        siblingVisual.userEditedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        siblingVisual.suggestionTitleSnapshot = item.title
        siblingVisual.suggestionModelID = "manual"
        siblingVisual.suggestionGeneratedAt = nil
        siblingVisual.updatedAt = siblingVisual.userEditedAt ?? siblingVisual.updatedAt
        siblingVisual.clientMutationID = UUID()
        try siblingContext.save()

        let outcome = try writer.applyVisualSuggestion(
            baseline: baseline,
            result: LLMChecklistVisualSuggestionResult(
                iconName: "book",
                colorHex: "16A34A",
                reason: "Suggested automatically",
                modelID: "test-model"
            )
        )

        #expect(outcome.didMutate == false)
        let persisted = try #require(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<ChecklistItemVisual>())
                .first(where: { $0.id == visual.id })
        )
        #expect(persisted.iconName == "paintbrush")
        #expect(persisted.colorHex == "EF4444")
        #expect(persisted.userEditedAt != nil)
    }

    @Test
    func freshVisualSuggestionAppliesOnlyAgainstItsCapturedRevision() throws {
        let context = try makeTestContext()
        let task = try makeTask(in: context, title: "Visual owner")
        let writer = coordinator(container: context.container, deviceID: "writer")
        _ = try writer.add(taskID: task.id, title: "Prepare deck")

        let item = try #require(try visibleItems(in: context.container).first)
        let visual = try #require(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<ChecklistItemVisual>())
                .first(where: { $0.checklistItemID == item.id })
        )
        let baseline = ChecklistVisualSuggestionBaseline(
            item: item,
            visual: visual,
            normalizedTitle: ChecklistVisualSuggestionPolicy().normalizedTitle(item.title)
        )

        let outcome = try writer.applyVisualSuggestion(
            baseline: baseline,
            result: LLMChecklistVisualSuggestionResult(
                iconName: "book",
                colorHex: "16A34A",
                reason: "Suggested automatically",
                modelID: "test-model"
            )
        )

        #expect(outcome.didMutate)
        let persisted = try #require(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<ChecklistItemVisual>())
                .first(where: { $0.id == visual.id })
        )
        #expect(persisted.iconName == "book")
        #expect(persisted.colorHex == "16A34A")
        #expect(persisted.userEditedAt == nil)
        #expect(persisted.suggestionModelID == "test-model")
    }

    private func makeTask(in context: ModelContext, title: String) throws -> TaskNode {
        try SwiftDataTaskRepository(context: context, deviceID: "seed").createTask(
            title: title,
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
    }

    private func coordinator(
        container: ModelContainer,
        deviceID: String
    ) -> StoreScopedChecklistCommandCoordinator {
        StoreScopedChecklistCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: deviceID
        )
    }

    private func visibleItems(in container: ModelContainer) throws -> [ChecklistItem] {
        try ModelContext(container)
            .fetch(FetchDescriptor<ChecklistItem>())
            .visibleDeduplicatedByID()
    }
}
