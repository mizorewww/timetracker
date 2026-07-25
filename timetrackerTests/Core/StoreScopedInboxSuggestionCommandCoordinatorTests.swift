import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedInboxSuggestionCommandCoordinatorTests {
    @Test
    func staleManualDraftCannotOverwriteANewerInboxTitle() throws {
        let context = try makeTestContext()
        let task = try createTask(in: context)
        let item = try insertItem(title: "Original title", into: context)
        var draft = InboxSuggestionEditorDraft(item: item, fallbackTaskID: task.id)
        draft.taskID = task.id
        draft.reason = "Manual route"
        let baseline = InboxItemMutationBaseline(item: item)

        let siblingContext = ModelContext(context.container)
        let siblingItem = try #require(try inboxItem(id: item.id, in: siblingContext))
        try InboxCommandHandler().updateTitle(
            siblingItem,
            title: "Edited in another scene",
            context: siblingContext,
            deviceID: "sibling"
        )

        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try coordinator(container: context.container).saveSuggestionDraft(
                baseline: baseline,
                draft: draft
            )
        }

        let persistedItem = try #require(try inboxItem(id: item.id, in: ModelContext(context.container)))
        #expect(persistedItem.title == "Edited in another scene")
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<InboxSuggestion>()).isEmpty)
    }

    @Test
    func applyUsesFreshChecklistOrderingAndPublishesBothDomains() throws {
        let context = try makeTestContext()
        let task = try createTask(in: context)
        let item = try insertItem(
            title: "  Prepare release notes  ",
            notes: "Keep the launch context",
            into: context
        )
        let suggestion = try insertSuggestion(
            for: item,
            destination: .checklist(taskID: task.id),
            iconName: "sparkles",
            colorHex: "16A34A",
            modelID: "route-model",
            into: context
        )
        let baseline = InboxSuggestionApplyBaseline(item: item, suggestion: suggestion)

        let siblingContext = ModelContext(context.container)
        siblingContext.insert(
            ChecklistItem(
                taskID: task.id,
                title: "Existing checklist item",
                sortOrder: 40,
                deviceID: "sibling"
            )
        )
        try siblingContext.save()

        let outcome = try coordinator(container: context.container).applySuggestion(baseline: baseline)
        guard case let .checklist(
            checklistItemID,
            destinationTaskID,
            affectedAncestorIDs
        ) = outcome.creation else {
            Issue.record("Expected a checklist route")
            return
        }

        #expect(outcome.didMutate)
        #expect(destinationTaskID == task.id)
        #expect(affectedAncestorIDs.isEmpty)
        #expect(outcome.events.contains(.inboxChanged(itemIDs: [item.id])))
        #expect(outcome.events.contains(
            .checklistChanged(taskID: task.id, affectedAncestorIDs: [])
        ))
        let freshContext = ModelContext(context.container)
        let createdChecklistItem = try #require(
            try freshContext.fetch(FetchDescriptor<ChecklistItem>())
                .first(where: { $0.id == checklistItemID })
        )
        #expect(createdChecklistItem.title == "Prepare release notes")
        #expect(createdChecklistItem.sortOrder == 50)
        let visual = try #require(
            try freshContext.fetch(FetchDescriptor<ChecklistItemVisual>())
                .first(where: { $0.checklistItemID == checklistItemID })
        )
        #expect(visual.iconName == "sparkles")
        #expect(visual.colorHex == "16A34A")
        #expect(visual.suggestionTitleSnapshot == "Prepare release notes")
        #expect(visual.suggestionModelID == "route-model")
        #expect(
            visual.suggestionGeneratedAt ==
                Date(timeIntervalSinceReferenceDate: 42000)
        )
        #expect(visual.userEditedAt == nil)
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt != nil)
        #expect(
            try freshContext.fetch(FetchDescriptor<InboxSuggestion>())
                .first(where: { $0.id == suggestion.id })?.deletedAt != nil
        )
    }

    @Test
    func staleSuggestionBaselineCannotCreateAChecklistItem() throws {
        let context = try makeTestContext()
        let task = try createTask(in: context)
        let item = try insertItem(title: "Prepare launch", into: context)
        let suggestion = try insertSuggestion(
            for: item,
            destination: .checklist(taskID: task.id),
            into: context
        )
        let baseline = InboxSuggestionApplyBaseline(item: item, suggestion: suggestion)

        let siblingContext = ModelContext(context.container)
        let siblingItem = try #require(try inboxItem(id: item.id, in: siblingContext))
        try InboxCommandHandler().upsertSuggestion(
            item: siblingItem,
            result: suggestionResult(
                destination: .checklist(taskID: task.id),
                reason: "A newer route"
            ),
            context: siblingContext,
            deviceID: "sibling"
        )

        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try coordinator(container: context.container).applySuggestion(baseline: baseline)
        }
        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt == nil)
    }

    @Test
    func applyRejectsATaskThatBecameUnavailableBeforeTheLock() throws {
        let context = try makeTestContext()
        let task = try createTask(in: context)
        let item = try insertItem(title: "Prepare launch", into: context)
        let suggestion = try insertSuggestion(
            for: item,
            destination: .checklist(taskID: task.id),
            into: context
        )
        let baseline = InboxSuggestionApplyBaseline(item: item, suggestion: suggestion)

        let siblingContext = ModelContext(context.container)
        try SwiftDataTaskRepository(
            context: siblingContext,
            deviceID: "sibling"
        ).archiveTask(taskID: task.id)

        #expect(throws: StoreScopedInboxMutationError.taskUnavailable) {
            try coordinator(container: context.container).applySuggestion(baseline: baseline)
        }
        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt == nil)
    }

    @Test
    func invalidDestinationKindCannotCreateOrConsumeAnything() throws {
        let context = try makeTestContext()
        let task = try createTask(in: context)
        let item = try insertItem(title: "Keep the invalid route", into: context)
        let suggestion = try insertSuggestion(
            for: item,
            destination: .checklist(taskID: task.id),
            into: context
        )
        suggestion.destinationKindRaw = "futureDestination"
        try context.save()
        let baseline = InboxSuggestionApplyBaseline(
            item: item,
            suggestion: suggestion
        )

        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try coordinator(container: context.container)
                .applySuggestion(baseline: baseline)
        }

        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty)
        #expect(try freshContext.fetch(FetchDescriptor<TaskNode>()).count == 1)
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt == nil)
        #expect(
            try freshContext.fetch(FetchDescriptor<InboxSuggestion>())
                .first?.deletedAt == nil
        )
    }

    @Test
    func childTaskSuggestionUsesTheSharedRouteCoreAndConsumesLogicalSiblings() throws {
        let context = try makeTestContext()
        let root = try createTask(title: "Project", in: context)
        let parent = try createTask(
            title: "Release",
            parentID: root.id,
            in: context
        )
        let item = try insertItem(
            title: "  Prepare screenshots  ",
            notes: "Keep the release context",
            into: context
        )
        let suggestion = try insertSuggestion(
            for: item,
            destination: .childTask(parentTaskID: parent.id),
            iconName: "photo",
            colorHex: "FF9500",
            into: context
        )
        let logicalSibling = InboxItem(
            title: item.title,
            deviceID: "older-device"
        )
        logicalSibling.suggestionContextID = item.effectiveSuggestionContextID
        logicalSibling.suggestionRevisionID = item.effectiveSuggestionRevisionID
        logicalSibling.updatedAt = item.updatedAt.addingTimeInterval(-10)
        context.insert(logicalSibling)
        let siblingSuggestion = InboxSuggestion(
            inboxItemID: logicalSibling.id,
            inboxItemContextID: logicalSibling.effectiveSuggestionContextID,
            inboxItemRevisionID: logicalSibling.effectiveSuggestionRevisionID,
            taskID: parent.id,
            destinationKind: .childTask,
            reason: "Older duplicate",
            iconName: "photo",
            colorHex: "FF9500",
            modelID: "test",
            titleSnapshot: item.title,
            generatedAt: suggestion.generatedAt.addingTimeInterval(-10),
            deviceID: "older-device"
        )
        siblingSuggestion.updatedAt = suggestion.updatedAt.addingTimeInterval(-10)
        context.insert(siblingSuggestion)
        try context.save()

        let outcome = try coordinator(container: context.container).applySuggestion(
            baseline: InboxSuggestionApplyBaseline(item: item, suggestion: suggestion)
        )
        guard case let .task(taskID, affectedAncestorIDs) = outcome.creation else {
            Issue.record("Expected a child-task route")
            return
        }

        #expect(affectedAncestorIDs == [root.id, parent.id])
        #expect(outcome.events.contains(.inboxChanged(itemIDs: [item.id])))
        #expect(outcome.events.contains(.taskChanged(
            taskID: taskID,
            affectedAncestorIDs: [root.id, parent.id]
        )))
        let freshContext = ModelContext(context.container)
        let createdTask = try #require(
            try SwiftDataTaskRepository(
                context: freshContext,
                deviceID: "test"
            ).task(id: taskID)
        )
        #expect(createdTask.title == "Prepare screenshots")
        #expect(createdTask.notes == "Keep the release context")
        #expect(createdTask.parentID == parent.id)
        #expect(createdTask.iconName == "photo")
        #expect(createdTask.colorHex == "FF9500")
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt != nil)
        #expect(try inboxItem(id: logicalSibling.id, in: freshContext)?.deletedAt != nil)
        let persistedSuggestions = try freshContext.fetch(
            FetchDescriptor<InboxSuggestion>()
        )
        #expect(
            persistedSuggestions.first(where: { $0.id == suggestion.id })?.deletedAt != nil
        )
        #expect(
            persistedSuggestions.first(where: { $0.id == siblingSuggestion.id })?.deletedAt != nil
        )
    }

    @Test
    func categorySuggestionCreatesAStyledRootTaskAndPreservesNotes() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let category = try repository.createCategory(
            title: "Personal",
            colorHex: "16A34A",
            iconName: "person"
        )
        let item = try insertItem(
            title: "Plan weekend",
            notes: "Book the train first",
            into: context
        )
        let suggestion = try insertSuggestion(
            for: item,
            destination: .category(categoryID: category.id),
            iconName: "tram.fill",
            colorHex: "AF52DE",
            into: context
        )

        let outcome = try coordinator(container: context.container).applySuggestion(
            baseline: InboxSuggestionApplyBaseline(item: item, suggestion: suggestion)
        )
        guard case let .task(taskID, affectedAncestorIDs) = outcome.creation else {
            Issue.record("Expected a category-task route")
            return
        }

        #expect(affectedAncestorIDs.isEmpty)
        #expect(outcome.events.contains(.taskChanged(
            taskID: taskID,
            affectedAncestorIDs: []
        )))
        let freshContext = ModelContext(context.container)
        let freshRepository = SwiftDataTaskRepository(
            context: freshContext,
            deviceID: "test"
        )
        let createdTask = try #require(try freshRepository.task(id: taskID))
        #expect(createdTask.title == "Plan weekend")
        #expect(createdTask.notes == "Book the train first")
        #expect(createdTask.parentID == nil)
        #expect(createdTask.iconName == "tram.fill")
        #expect(createdTask.colorHex == "AF52DE")
        #expect(try freshRepository.categoryID(forRootTaskID: taskID) == category.id)
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt != nil)
    }

    @Test
    func categorySuggestionRejectsADeletedTargetWithoutSideEffects() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let category = try repository.createCategory(title: "Temporary")
        let item = try insertItem(title: "Keep me", into: context)
        let suggestion = try insertSuggestion(
            for: item,
            destination: .category(categoryID: category.id),
            into: context
        )
        let baseline = InboxSuggestionApplyBaseline(item: item, suggestion: suggestion)

        let siblingContext = ModelContext(context.container)
        try SwiftDataTaskRepository(
            context: siblingContext,
            deviceID: "sibling"
        ).softDeleteCategory(categoryID: category.id)

        #expect(throws: StoreScopedInboxMutationError.categoryUnavailable) {
            try coordinator(container: context.container).applySuggestion(
                baseline: baseline
            )
        }

        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<TaskNode>()).isEmpty)
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt == nil)
        #expect(
            try freshContext.fetch(FetchDescriptor<InboxSuggestion>())
                .first(where: { $0.id == suggestion.id })?.deletedAt == nil
        )
    }

    @Test
    func consumedSuggestionBaselineCannotCreateASecondDestination() throws {
        let context = try makeTestContext()
        let parent = try createTask(in: context)
        let item = try insertItem(title: "Route once", into: context)
        let suggestion = try insertSuggestion(
            for: item,
            destination: .childTask(parentTaskID: parent.id),
            into: context
        )
        let baseline = InboxSuggestionApplyBaseline(item: item, suggestion: suggestion)
        let coordinator = coordinator(container: context.container)

        _ = try coordinator.applySuggestion(baseline: baseline)
        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try coordinator.applySuggestion(baseline: baseline)
        }

        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<TaskNode>()).count == 2)
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
    }

    @Test
    func failedInboxCleanupRollsBackSuggestedChildTaskCreation() throws {
        let context = try makeTestContext()
        let parent = try createTask(in: context)
        let item = try insertItem(title: "Stay atomic", into: context)
        let suggestion = try insertSuggestion(
            for: item,
            destination: .childTask(parentTaskID: parent.id),
            into: context
        )
        let invalidDuplicate = try insertSuggestion(
            for: item,
            destination: .childTask(parentTaskID: parent.id),
            reason: "Older duplicate",
            into: context
        )
        invalidDuplicate.modelID = String(
            repeating: "m",
            count: SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount + 1
        )
        invalidDuplicate.updatedAt = suggestion.updatedAt.addingTimeInterval(-10)
        try context.save()

        #expect(throws: InboxPersistenceValidationError.self) {
            try coordinator(container: context.container).applySuggestion(
                baseline: InboxSuggestionApplyBaseline(
                    item: item,
                    suggestion: suggestion
                )
            )
        }

        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<TaskNode>()).map(\.id) == [parent.id])
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt == nil)
        let persistedSuggestions = try freshContext.fetch(
            FetchDescriptor<InboxSuggestion>()
        )
        #expect(
            persistedSuggestions.first(where: { $0.id == suggestion.id })?.deletedAt == nil
        )
        #expect(
            persistedSuggestions.first(where: { $0.id == invalidDuplicate.id })?.deletedAt == nil
        )
    }

    @Test
    func generatedSuggestionSilentlyDropsAfterATitleRevisionChanges() throws {
        let context = try makeTestContext()
        let task = try createTask(in: context)
        let item = try insertItem(title: "Original title", into: context)
        let requestedIdentity = item.suggestionIdentity

        let siblingContext = ModelContext(context.container)
        let siblingItem = try #require(try inboxItem(id: item.id, in: siblingContext))
        try InboxCommandHandler().updateTitle(
            siblingItem,
            title: "Newer title",
            context: siblingContext,
            deviceID: "sibling"
        )

        let outcome = try coordinator(container: context.container).storeGeneratedSuggestion(
            itemID: item.id,
            requestedTitle: item.title,
            requestedIdentity: requestedIdentity,
            result: suggestionResult(
                destination: .checklist(taskID: task.id),
                reason: "Old response"
            )
        )

        #expect(outcome.didMutate == false)
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<InboxSuggestion>()).isEmpty)
    }

    @Test
    func generatedSuggestionRemainsValidAfterAPureReorder() throws {
        let context = try makeTestContext()
        let task = try createTask(in: context)
        let first = try insertItem(title: "First", sortOrder: 10, into: context)
        let second = try insertItem(title: "Second", sortOrder: 20, into: context)
        let requestedIdentity = first.suggestionIdentity

        let siblingContext = ModelContext(context.container)
        try InboxCommandHandler().reorderOpenItems(
            orderedItemIDs: [second.id, first.id],
            context: siblingContext,
            deviceID: "sibling"
        )

        let outcome = try coordinator(container: context.container).storeGeneratedSuggestion(
            itemID: first.id,
            requestedTitle: first.title,
            requestedIdentity: requestedIdentity,
            result: suggestionResult(
                destination: .checklist(taskID: task.id),
                reason: "Still current"
            )
        )

        #expect(outcome.didMutate)
        let persistedSuggestions = try ModelContext(context.container)
            .fetch(FetchDescriptor<InboxSuggestion>())
        #expect(persistedSuggestions.count == 1)
        #expect(persistedSuggestions.first?.taskID == task.id)
        #expect(persistedSuggestions.first?.destinationKind == .checklist)
    }

    @Test
    func generatedSuggestionPersistsItsTypedCategoryDestination() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let category = try repository.createCategory(title: "Work")
        let item = try insertItem(title: "Prepare planning", into: context)

        let outcome = try coordinator(container: context.container)
            .storeGeneratedSuggestion(
                itemID: item.id,
                requestedTitle: item.title,
                requestedIdentity: item.suggestionIdentity,
                result: suggestionResult(
                    destination: .category(categoryID: category.id),
                    reason: "A category-level action"
                )
            )

        #expect(outcome.didMutate)
        let freshContext = ModelContext(context.container)
        let persistedItem = try #require(try inboxItem(id: item.id, in: freshContext))
        let suggestion = try #require(
            try freshContext.fetch(FetchDescriptor<InboxSuggestion>()).first
        )
        #expect(suggestion.destinationKind == .category)
        #expect(suggestion.taskID == category.id)
        #expect(suggestion.manualRouteDestination == .category(categoryID: category.id))
        #expect(persistedItem.suggestedTaskID == nil)
    }

    @Test
    func generatedSuggestionDropsAnUnavailableCategoryWithoutMutation() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let category = try repository.createCategory(title: "Temporary")
        let item = try insertItem(title: "Keep unchanged", into: context)
        try repository.softDeleteCategory(categoryID: category.id)

        let outcome = try coordinator(container: context.container)
            .storeGeneratedSuggestion(
                itemID: item.id,
                requestedTitle: item.title,
                requestedIdentity: item.suggestionIdentity,
                result: suggestionResult(
                    destination: .category(categoryID: category.id),
                    reason: "No longer available"
                )
            )

        #expect(outcome.didMutate == false)
        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<InboxSuggestion>()).isEmpty)
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt == nil)
    }

    private func coordinator(container: ModelContainer) -> StoreScopedInboxCommandCoordinator {
        StoreScopedInboxCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "test",
            nowProvider: {
                Date(timeIntervalSinceReferenceDate: 42000)
            }
        )
    }

    private func createTask(in context: ModelContext) throws -> TaskNode {
        try createTask(title: "Target task", in: context)
    }

    private func createTask(
        title: String,
        parentID: UUID? = nil,
        in context: ModelContext
    ) throws -> TaskNode {
        try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: title,
            parentID: parentID,
            colorHex: nil,
            iconName: nil
        )
    }

    private func insertItem(
        title: String,
        notes: String? = nil,
        sortOrder: Double = 10,
        into context: ModelContext
    ) throws -> InboxItem {
        let item = InboxItem(title: title, sortOrder: sortOrder, deviceID: "test")
        item.notes = notes
        context.insert(item)
        try context.save()
        return item
    }

    private func insertSuggestion(
        for item: InboxItem,
        destination: InboxManualRouteDestination,
        reason: String = "Matched task",
        iconName: String = "checkmark.circle",
        colorHex: String = "1677FF",
        modelID: String = "test",
        into context: ModelContext
    ) throws -> InboxSuggestion {
        let suggestion = InboxSuggestion(
            inboxItemID: item.id,
            inboxItemContextID: item.effectiveSuggestionContextID,
            inboxItemRevisionID: item.effectiveSuggestionRevisionID,
            taskID: destination.persistenceTargetID,
            destinationKind: destination.suggestionDestinationKind,
            reason: reason,
            iconName: iconName,
            colorHex: colorHex,
            modelID: modelID,
            titleSnapshot: item.title,
            deviceID: "test"
        )
        context.insert(suggestion)
        try context.save()
        return suggestion
    }

    private func suggestionResult(
        destination: InboxManualRouteDestination,
        reason: String
    ) -> LLMInboxSuggestionResult {
        LLMInboxSuggestionResult(
            destination: destination,
            reason: reason,
            iconName: "checkmark.circle",
            colorHex: "1677FF",
            modelID: "test"
        )
    }

    private func inboxItem(id: UUID, in context: ModelContext) throws -> InboxItem? {
        try context.fetch(FetchDescriptor<InboxItem>()).first { $0.id == id }
    }
}
