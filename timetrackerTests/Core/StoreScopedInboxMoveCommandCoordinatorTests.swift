import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedInboxMoveCommandCoordinatorTests {
    @Test
    func checklistRouteUsesFreshOrderingAndPublishesInboxAndChecklistChanges() throws {
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
        let baseline = InboxManualRouteBaseline(item: item)

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

        let outcome = try coordinator(container: context.container).route(
            baseline: baseline,
            destination: .checklist(taskID: task.id)
        )
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
        #expect(affectedAncestorIDs == [parent.id])
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
                .first { $0.id == checklistItemID }
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
    func aConsumedBaselineCannotCreateAnotherDestination() throws {
        let context = try makeTestContext()
        let task = try createTask(title: "Target", in: context)
        let item = try insertItem(title: "Route once", into: context)
        let baseline = InboxManualRouteBaseline(item: item)
        let coordinator = coordinator(container: context.container)

        _ = try coordinator.route(
            baseline: baseline,
            destination: .checklist(taskID: task.id)
        )

        #expect(throws: StoreScopedInboxMutationError.inboxChanged) {
            try coordinator.route(
                baseline: baseline,
                destination: .childTask(parentTaskID: task.id)
            )
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
        let itemBaseline = InboxManualRouteBaseline(item: item)
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
            try coordinator(container: itemContext.container).route(
                baseline: itemBaseline,
                destination: .childTask(parentTaskID: itemTask.id)
            )
        }

        let taskContext = try makeTestContext()
        let unavailableTask = try createTask(title: "Closing", in: taskContext)
        let untouchedItem = try insertItem(title: "Keep me", into: taskContext)
        let taskBaseline = InboxManualRouteBaseline(item: untouchedItem)
        let taskSiblingContext = ModelContext(taskContext.container)
        try SwiftDataTaskRepository(
            context: taskSiblingContext,
            deviceID: "sibling"
        ).archiveTask(taskID: unavailableTask.id)

        #expect(throws: StoreScopedInboxMutationError.taskUnavailable) {
            try coordinator(container: taskContext.container).route(
                baseline: taskBaseline,
                destination: .checklist(taskID: unavailableTask.id)
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
        let baseline = InboxManualRouteBaseline(item: item)

        #expect(throws: InboxPersistenceValidationError.self) {
            try coordinator(container: context.container).route(
                baseline: baseline,
                destination: .checklist(taskID: task.id)
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
        let baseline = InboxManualRouteBaseline(item: item)
        let requestedIdentity = item.suggestionIdentity
        let coordinator = coordinator(container: context.container)

        _ = try coordinator.route(
            baseline: baseline,
            destination: .checklist(taskID: task.id)
        )
        let outcome = try coordinator.storeGeneratedSuggestion(
            itemID: item.id,
            requestedTitle: item.title,
            requestedIdentity: requestedIdentity,
            result: LLMInboxSuggestionResult(
                destination: .checklist(taskID: task.id),
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

    @Test
    func childTaskRouteCreatesAChildAndInvalidatesItsAncestors() throws {
        let context = try makeTestContext()
        let root = try createTask(title: "Project", in: context)
        let parent = try createTask(
            title: "Release",
            parentID: root.id,
            in: context
        )
        let item = try insertItem(
            title: "  Prepare screenshots  ",
            into: context
        )
        item.notes = "Keep the release context"
        try context.save()

        let outcome = try coordinator(container: context.container).route(
            baseline: InboxManualRouteBaseline(item: item),
            destination: .childTask(parentTaskID: parent.id)
        )
        guard case let .task(taskID, affectedAncestorIDs) = outcome.creation else {
            Issue.record("Expected a child-task route")
            return
        }

        #expect(affectedAncestorIDs == [root.id, parent.id])
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
        #expect(createdTask.depth == parent.depth + 1)
        #expect(
            try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty
        )
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt != nil)
    }

    @Test
    func categoryRouteCreatesARootTaskAssignedToTheSelectedCategory() throws {
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
        let item = try insertItem(title: "Plan weekend", into: context)

        let outcome = try coordinator(container: context.container).route(
            baseline: InboxManualRouteBaseline(item: item),
            destination: .category(categoryID: category.id)
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
        #expect(createdTask.parentID == nil)
        #expect(try freshRepository.categoryID(forRootTaskID: taskID) == category.id)
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt != nil)
    }

    @Test
    func categoryRouteRejectsADeletedCategoryWithoutConsumingTheInboxItem() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let category = try repository.createCategory(title: "Temporary")
        let item = try insertItem(title: "Keep me", into: context)
        let baseline = InboxManualRouteBaseline(item: item)
        let siblingContext = ModelContext(context.container)
        try SwiftDataTaskRepository(
            context: siblingContext,
            deviceID: "sibling"
        ).softDeleteCategory(categoryID: category.id)

        #expect(throws: StoreScopedInboxMutationError.categoryUnavailable) {
            try coordinator(container: context.container).route(
                baseline: baseline,
                destination: .category(categoryID: category.id)
            )
        }

        let freshContext = ModelContext(context.container)
        #expect(
            try freshContext.fetch(FetchDescriptor<TaskNode>()).isEmpty
        )
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt == nil)
    }

    @Test
    func failedInboxCleanupRollsBackAChildTaskCreation() throws {
        let context = try makeTestContext()
        let parent = try createTask(title: "Target", in: context)
        let item = try insertItem(title: "Stay atomic", into: context)
        let invalidSuggestion = try insertSuggestion(
            for: item,
            taskID: parent.id,
            into: context
        )
        invalidSuggestion.modelID = String(
            repeating: "m",
            count: SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount + 1
        )
        try context.save()

        #expect(throws: InboxPersistenceValidationError.self) {
            try coordinator(container: context.container).route(
                baseline: InboxManualRouteBaseline(item: item),
                destination: .childTask(parentTaskID: parent.id)
            )
        }

        let freshContext = ModelContext(context.container)
        let tasks = try freshContext.fetch(FetchDescriptor<TaskNode>())
        #expect(tasks.map(\.id) == [parent.id])
        #expect(try inboxItem(id: item.id, in: freshContext)?.deletedAt == nil)
        #expect(
            try freshContext.fetch(FetchDescriptor<InboxSuggestion>())
                .first { $0.id == invalidSuggestion.id }?.deletedAt == nil
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
