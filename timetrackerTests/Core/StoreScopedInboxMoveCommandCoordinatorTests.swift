import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedInboxMoveCommandCoordinatorTests {
    @Test
    func moveUsesFreshOrderingAndPublishesInboxAndChecklistChanges() throws {
        let context = try makeTestContext()
        let parent = try createTask(title: "Project", in: context)
        let task = try createTask(
            title: "Target",
            parentID: parent.id,
            in: context
        )
        let item = try insertItem(title: "  Prepare release notes  ", into: context)
        let suggestion = try insertSuggestion(
            for: item,
            taskID: task.id,
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
        try context.save()
        let siblingSuggestion = try insertSuggestion(
            for: logicalSibling,
            taskID: task.id,
            into: context
        )
        let baseline = InboxMoveToTaskBaseline(item: item)

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

        let outcome = try coordinator(container: context.container).moveToTask(
            baseline: baseline,
            taskID: task.id
        )

        #expect(outcome.didMutate)
        #expect(outcome.taskID == task.id)
        #expect(outcome.affectedAncestorIDs == [parent.id])
        #expect(outcome.events.contains(.inboxChanged(itemIDs: [item.id])))
        #expect(outcome.events.contains(
            .checklistChanged(
                taskID: task.id,
                affectedAncestorIDs: [parent.id]
            )
        ))

        let freshContext = ModelContext(context.container)
        let checklistItem = try #require(
            try freshContext.fetch(FetchDescriptor<ChecklistItem>())
                .first { $0.id == outcome.checklistItemID }
        )
        #expect(checklistItem.title == "Prepare release notes")
        #expect(checklistItem.sortOrder == 50)
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt != nil)
        #expect(
            try freshContext.fetch(FetchDescriptor<InboxSuggestion>())
                .first { $0.id == suggestion.id }?.deletedAt != nil
        )
        #expect(
            try freshContext.fetch(FetchDescriptor<InboxSuggestion>())
                .first { $0.id == siblingSuggestion.id }?.deletedAt != nil
        )
        #expect(try inboxItem(
            id: logicalSibling.id,
            in: freshContext
        )?.deletedAt != nil)
        let visual = try #require(
            try freshContext.fetch(FetchDescriptor<ChecklistItemVisual>())
                .first { $0.checklistItemID == checklistItem.id }
        )
        #expect(visual.iconName == ChecklistVisualSanitizer.defaultIcon)
        #expect(visual.colorHex == ChecklistVisualSanitizer.defaultColor)
    }

    @Test
    func aConsumedBaselineCannotCreateADuplicateChecklistItem() throws {
        let context = try makeTestContext()
        let task = try createTask(title: "Target", in: context)
        let item = try insertItem(title: "Route once", into: context)
        let baseline = InboxMoveToTaskBaseline(item: item)
        let coordinator = coordinator(container: context.container)

        _ = try coordinator.moveToTask(baseline: baseline, taskID: task.id)

        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try coordinator.moveToTask(baseline: baseline, taskID: task.id)
        }
        #expect(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<ChecklistItem>())
                .count == 1
        )
    }

    @Test
    func moveRejectsAnItemOrTaskThatChangedWhileChoosing() throws {
        let itemContext = try makeTestContext()
        let itemTask = try createTask(title: "Target", in: itemContext)
        let item = try insertItem(title: "Original", into: itemContext)
        let itemBaseline = InboxMoveToTaskBaseline(item: item)
        let siblingContext = ModelContext(itemContext.container)
        let siblingItem = try #require(
            try inboxItem(id: item.id, in: siblingContext)
        )
        try InboxCommandHandler().updateTitle(
            siblingItem,
            title: "Changed elsewhere",
            context: siblingContext,
            deviceID: "sibling"
        )

        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try coordinator(container: itemContext.container).moveToTask(
                baseline: itemBaseline,
                taskID: itemTask.id
            )
        }

        let taskContext = try makeTestContext()
        let unavailableTask = try createTask(title: "Closing", in: taskContext)
        let untouchedItem = try insertItem(title: "Keep me", into: taskContext)
        let taskBaseline = InboxMoveToTaskBaseline(item: untouchedItem)
        let taskSiblingContext = ModelContext(taskContext.container)
        try SwiftDataTaskRepository(
            context: taskSiblingContext,
            deviceID: "sibling"
        ).setTaskStatus(taskID: unavailableTask.id, status: .completed)

        #expect(throws: StoreScopedInboxMutationError.taskUnavailable) {
            try coordinator(container: taskContext.container).moveToTask(
                baseline: taskBaseline,
                taskID: unavailableTask.id
            )
        }
        #expect(
            try ModelContext(taskContext.container)
                .fetch(FetchDescriptor<ChecklistItem>())
                .isEmpty
        )
        #expect(
            try inboxItem(
                id: untouchedItem.id,
                in: ModelContext(taskContext.container)
            )?.deletedAt == nil
        )
    }

    @Test
    func invalidSuggestionMetadataRollsBackTheWholeMove() throws {
        let context = try makeTestContext()
        let task = try createTask(title: "Target", in: context)
        let item = try insertItem(title: "Stay atomic", into: context)
        let invalidSuggestion = try insertSuggestion(
            for: item,
            taskID: task.id,
            into: context
        )
        invalidSuggestion.modelID = String(
            repeating: "m",
            count: SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount + 1
        )
        try context.save()
        let baseline = InboxMoveToTaskBaseline(item: item)

        #expect(throws: InboxPersistenceValidationError.self) {
            try coordinator(container: context.container).moveToTask(
                baseline: baseline,
                taskID: task.id
            )
        }

        let freshContext = ModelContext(context.container)
        #expect(
            try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty
        )
        #expect(
            try freshContext.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty
        )
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt == nil)
        #expect(
            try freshContext.fetch(FetchDescriptor<InboxSuggestion>())
                .first { $0.id == invalidSuggestion.id }?.deletedAt == nil
        )
    }

    @Test
    func lateSuggestionResponseIsIgnoredAfterManualMove() throws {
        let context = try makeTestContext()
        let task = try createTask(title: "Target", in: context)
        let item = try insertItem(title: "Already routed", into: context)
        let baseline = InboxMoveToTaskBaseline(item: item)
        let requestedIdentity = item.suggestionIdentity
        let coordinator = coordinator(container: context.container)

        _ = try coordinator.moveToTask(baseline: baseline, taskID: task.id)
        let outcome = try coordinator.storeGeneratedSuggestion(
            itemID: item.id,
            requestedTitle: item.title,
            requestedIdentity: requestedIdentity,
            result: LLMInboxSuggestionResult(
                taskID: task.id,
                reason: "Arrived too late",
                iconName: "sparkles",
                colorHex: "1677FF",
                modelID: "test"
            )
        )

        #expect(outcome.didMutate == false)
        #expect(
            try ModelContext(context.container)
                .fetch(FetchDescriptor<InboxSuggestion>())
                .isEmpty
        )
    }

    private func coordinator(
        container: ModelContainer
    ) -> StoreScopedInboxCommandCoordinator {
        StoreScopedInboxCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "test"
        )
    }

    private func createTask(
        title: String,
        parentID: UUID? = nil,
        in context: ModelContext
    ) throws -> TaskNode {
        try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: title,
            parentID: parentID,
            colorHex: nil,
            iconName: nil
        )
    }

    private func insertItem(
        title: String,
        into context: ModelContext
    ) throws -> InboxItem {
        let item = InboxItem(title: title, deviceID: "test")
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
            reason: "Suggested target",
            iconName: "sparkles",
            colorHex: "1677FF",
            modelID: "test",
            titleSnapshot: item.title,
            deviceID: "test"
        )
        context.insert(suggestion)
        try context.save()
        return suggestion
    }

    private func inboxItem(
        id: UUID,
        in context: ModelContext
    ) throws -> InboxItem? {
        try context.fetch(FetchDescriptor<InboxItem>())
            .first { $0.id == id }
    }
}
