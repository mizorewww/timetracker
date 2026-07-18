import Foundation

struct InboxMoveToTaskBaseline: Equatable, Sendable {
    let itemID: UUID
    let itemMutationID: UUID
    let itemIdentity: InboxSuggestionIdentity

    init(item: InboxItem) {
        itemID = item.id
        itemMutationID = item.clientMutationID
        itemIdentity = item.suggestionIdentity
    }
}

extension StoreScopedInboxCommandCoordinator {
    func moveToTask(
        baseline: InboxMoveToTaskBaseline,
        taskID: UUID
    ) throws -> InboxChecklistRouteOutcome {
        try withFreshLockedContext { context in
            guard let resolution = try visibleLogicalResolution(
                contextID: baseline.itemIdentity.contextID,
                context: context
            ) else {
                throw StoreScopedInboxMutationError.inboxChanged
            }

            let item = resolution.winner
            guard item.id == baseline.itemID,
                  item.clientMutationID == baseline.itemMutationID,
                  item.suggestionIdentity == baseline.itemIdentity,
                  item.isCompleted == false else {
                throw StoreScopedInboxMutationError.inboxChanged
            }

            let tasks = try trackableTasks(context: context)
            guard tasks.trackableIDs.contains(taskID) else {
                throw StoreScopedInboxMutationError.taskUnavailable
            }
            let existingChecklistItems = try visibleChecklistItems(
                taskID: taskID,
                context: context
            )
            let mutationIDBeforeMove = item.clientMutationID
            guard let checklistItem = try ChecklistCommandHandler().add(
                taskID: taskID,
                title: item.title,
                existingItems: existingChecklistItems,
                context: context,
                deviceID: deviceID
            ) else {
                throw StoreScopedInboxMutationError.inboxChanged
            }
            try InboxCommandHandler().softDelete(
                item,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
            let ancestorIDs = Set(
                StoreSelectionCoordinator().ancestorTaskIDs(
                    for: taskID,
                    taskByID: tasks.byID
                )
            )
            return InboxChecklistRouteOutcome(
                inboxItemID: item.id,
                checklistItemID: checklistItem.id,
                taskID: taskID,
                affectedAncestorIDs: ancestorIDs,
                didMutate: item.clientMutationID != mutationIDBeforeMove
            )
        }
    }
}
