import Foundation
import SwiftData

struct InboxManualRouteBaseline: Equatable, Sendable {
    let itemID: UUID
    let itemMutationID: UUID
    let itemIdentity: InboxSuggestionIdentity

    init(item: InboxItem) {
        itemID = item.id
        itemMutationID = item.clientMutationID
        itemIdentity = item.suggestionIdentity
    }
}

enum InboxManualRouteDestination: Equatable, Sendable {
    case childTask(parentTaskID: UUID)
    case category(categoryID: UUID)
    case checklist(taskID: UUID)
}

enum InboxManualRouteCreation: Equatable {
    case task(taskID: UUID, affectedAncestorIDs: Set<UUID>)
    case checklist(
        checklistItemID: UUID,
        taskID: UUID,
        affectedAncestorIDs: Set<UUID>
    )
}

struct InboxManualRouteOutcome: Equatable {
    let inboxItemID: UUID
    let creation: InboxManualRouteCreation
    let didMutate: Bool

    var events: Set<StoreDomainEvent> {
        guard didMutate else { return [] }
        var events: Set<StoreDomainEvent> = [
            .inboxChanged(itemIDs: [inboxItemID]),
        ]
        switch creation {
        case let .task(taskID, affectedAncestorIDs):
            events.insert(.taskChanged(
                taskID: taskID,
                affectedAncestorIDs: affectedAncestorIDs
            ))
        case let .checklist(_, taskID, affectedAncestorIDs):
            events.insert(.checklistChanged(
                taskID: taskID,
                affectedAncestorIDs: affectedAncestorIDs
            ))
        }
        return events
    }
}

extension StoreScopedInboxCommandCoordinator {
    func route(
        baseline: InboxManualRouteBaseline,
        destination: InboxManualRouteDestination
    ) throws -> InboxManualRouteOutcome {
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

            let mutationIDBeforeMove = item.clientMutationID
            let creation = try createDestination(
                destination,
                title: item.title,
                notes: item.notes,
                context: context
            )
            try InboxCommandHandler().softDelete(
                item,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
            return InboxManualRouteOutcome(
                inboxItemID: item.id,
                creation: creation,
                didMutate: item.clientMutationID != mutationIDBeforeMove
            )
        }
    }

    private func createDestination(
        _ destination: InboxManualRouteDestination,
        title: String,
        notes: String?,
        context: ModelContext
    ) throws -> InboxManualRouteCreation {
        switch destination {
        case let .childTask(parentTaskID):
            let tasks = try trackableTasks(context: context)
            guard tasks.trackableIDs.contains(parentTaskID) else {
                throw StoreScopedInboxMutationError.taskUnavailable
            }
            let repository = SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID
            )
            let task = try repository.createTask(
                title: title,
                parentID: parentTaskID,
                colorHex: nil,
                iconName: nil
            )
            try repository.updateTask(
                taskID: task.id,
                title: task.title,
                parentID: parentTaskID,
                categoryID: nil,
                colorHex: nil,
                iconName: nil,
                notes: notes,
                estimatedSeconds: nil,
                dueAt: nil
            )
            var affectedAncestorIDs = Set(
                StoreSelectionCoordinator().ancestorTaskIDs(
                    for: parentTaskID,
                    taskByID: tasks.byID
                )
            )
            affectedAncestorIDs.insert(parentTaskID)
            return .task(
                taskID: task.id,
                affectedAncestorIDs: affectedAncestorIDs
            )

        case let .category(categoryID):
            let repository = SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID
            )
            guard try repository.category(id: categoryID) != nil else {
                throw StoreScopedInboxMutationError.categoryUnavailable
            }
            let task = try repository.createTask(
                title: title,
                parentID: nil,
                categoryID: categoryID,
                colorHex: nil,
                iconName: nil
            )
            try repository.updateTask(
                taskID: task.id,
                title: task.title,
                parentID: nil,
                categoryID: categoryID,
                colorHex: nil,
                iconName: nil,
                notes: notes,
                estimatedSeconds: nil,
                dueAt: nil
            )
            return .task(taskID: task.id, affectedAncestorIDs: [])

        case let .checklist(taskID):
            let tasks = try trackableTasks(context: context)
            guard tasks.trackableIDs.contains(taskID) else {
                throw StoreScopedInboxMutationError.taskUnavailable
            }
            let existingChecklistItems = try visibleChecklistItems(
                taskID: taskID,
                context: context
            )
            guard let checklistItem = try ChecklistCommandHandler().add(
                taskID: taskID,
                title: title,
                existingItems: existingChecklistItems,
                context: context,
                deviceID: deviceID
            ) else {
                throw StoreScopedInboxMutationError.inboxChanged
            }
            let ancestorIDs = Set(
                StoreSelectionCoordinator().ancestorTaskIDs(
                    for: taskID,
                    taskByID: tasks.byID
                )
            )
            return .checklist(
                checklistItemID: checklistItem.id,
                taskID: taskID,
                affectedAncestorIDs: ancestorIDs
            )
        }
    }
}
