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
        let item = try insertItem(title: "Prepare release notes", into: context)
        let suggestion = try insertSuggestion(for: item, taskID: task.id, into: context)
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

        #expect(outcome.didMutate)
        #expect(outcome.taskID == task.id)
        #expect(outcome.events.contains(.inboxChanged(itemIDs: [item.id])))
        #expect(outcome.events.contains(
            .checklistChanged(taskID: task.id, affectedAncestorIDs: [])
        ))
        let freshContext = ModelContext(context.container)
        let createdChecklistItem = try #require(
            try freshContext.fetch(FetchDescriptor<ChecklistItem>())
                .first(where: { $0.id == outcome.checklistItemID })
        )
        #expect(createdChecklistItem.sortOrder == 50)
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt != nil)
    }

    @Test
    func staleSuggestionBaselineCannotCreateAChecklistItem() throws {
        let context = try makeTestContext()
        let task = try createTask(in: context)
        let item = try insertItem(title: "Prepare launch", into: context)
        let suggestion = try insertSuggestion(for: item, taskID: task.id, into: context)
        let baseline = InboxSuggestionApplyBaseline(item: item, suggestion: suggestion)

        let siblingContext = ModelContext(context.container)
        let siblingItem = try #require(try inboxItem(id: item.id, in: siblingContext))
        try InboxCommandHandler().upsertSuggestion(
            item: siblingItem,
            result: suggestionResult(taskID: task.id, reason: "A newer route"),
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
        let suggestion = try insertSuggestion(for: item, taskID: task.id, into: context)
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
            result: suggestionResult(taskID: task.id, reason: "Old response")
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
            result: suggestionResult(taskID: task.id, reason: "Still current")
        )

        #expect(outcome.didMutate)
        let persistedSuggestions = try ModelContext(context.container)
            .fetch(FetchDescriptor<InboxSuggestion>())
        #expect(persistedSuggestions.count == 1)
        #expect(persistedSuggestions.first?.taskID == task.id)
    }

    private func coordinator(container: ModelContainer) -> StoreScopedInboxCommandCoordinator {
        StoreScopedInboxCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "test"
        )
    }

    private func createTask(in context: ModelContext) throws -> TaskNode {
        try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: "Target task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
    }

    private func insertItem(
        title: String,
        sortOrder: Double = 10,
        into context: ModelContext
    ) throws -> InboxItem {
        let item = InboxItem(title: title, sortOrder: sortOrder, deviceID: "test")
        context.insert(item)
        try context.save()
        return item
    }

    private func insertSuggestion(
        for item: InboxItem,
        taskID: UUID,
        into context: ModelContext
    ) throws -> InboxSuggestion {
        let suggestion = InboxSuggestion(
            inboxItemID: item.id,
            inboxItemContextID: item.effectiveSuggestionContextID,
            inboxItemRevisionID: item.effectiveSuggestionRevisionID,
            taskID: taskID,
            reason: "Matched task",
            iconName: "checkmark.circle",
            colorHex: "1677FF",
            modelID: "test",
            titleSnapshot: item.title,
            deviceID: "test"
        )
        context.insert(suggestion)
        try context.save()
        return suggestion
    }

    private func suggestionResult(
        taskID: UUID,
        reason: String
    ) -> LLMInboxSuggestionResult {
        LLMInboxSuggestionResult(
            taskID: taskID,
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
