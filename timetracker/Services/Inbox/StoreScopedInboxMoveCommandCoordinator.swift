import Foundation
import SwiftData

struct InboxManualRouteBaseline: Equatable, Sendable {
    /// The row that presented the picker. This is retained only for clearing
    /// row-scoped UI state after a successful logical move.
    let itemID: UUID
    let itemIdentity: InboxSuggestionIdentity

    init(item: InboxItem) {
        itemID = item.id
        itemIdentity = item.suggestionIdentity
    }
}

nonisolated enum InboxManualRouteDestination: Equatable, Sendable {
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

struct InboxChecklistRouteProvenance {
    let titleSnapshot: String
    let modelID: String?
    let generatedAt: Date
}

struct InboxRouteCreationContent {
    let title: String
    let notes: String?
    let iconName: String?
    let colorHex: String?
    let checklistProvenance: InboxChecklistRouteProvenance?

    static func manual(item: PreparedInboxItemText) -> Self {
        Self(
            title: item.title,
            notes: item.notes,
            iconName: nil,
            colorHex: nil,
            checklistProvenance: nil
        )
    }

    static func suggested(
        item: PreparedInboxItemText,
        suggestion: PreparedInboxSuggestionText,
        appliedAt: Date
    ) -> Self {
        Self(
            title: item.title,
            notes: item.notes,
            iconName: suggestion.iconName,
            colorHex: suggestion.colorHex,
            checklistProvenance: InboxChecklistRouteProvenance(
                titleSnapshot: item.title,
                modelID: suggestion.modelID,
                generatedAt: appliedAt
            )
        )
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
            guard item.suggestionIdentity == baseline.itemIdentity,
                  item.isCompleted == false
            else {
                throw StoreScopedInboxMutationError.inboxChanged
            }

            let appliedAt = nowProvider()
            let preparedItem = try InboxPersistencePolicy.prepareItem(
                title: item.title,
                notes: item.notes,
                suggestionReason: item.suggestionReason
            )
            let mutationIDBeforeMove = item.clientMutationID
            let creation = try createRouteDestination(
                destination,
                content: .manual(item: preparedItem),
                context: context
            )
            try InboxCommandHandler().softDelete(
                item,
                context: context,
                now: appliedAt,
                deviceID: deviceID
            )
            return InboxManualRouteOutcome(
                inboxItemID: item.id,
                creation: creation,
                didMutate: item.clientMutationID != mutationIDBeforeMove
            )
        }
    }

    func createRouteDestination(
        _ destination: InboxManualRouteDestination,
        content: InboxRouteCreationContent,
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
                title: content.title,
                parentID: parentTaskID,
                colorHex: content.colorHex,
                iconName: content.iconName
            )
            try repository.updateTask(
                taskID: task.id,
                title: task.title,
                parentID: parentTaskID,
                categoryID: nil,
                colorHex: content.colorHex,
                iconName: content.iconName,
                notes: content.notes,
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
                title: content.title,
                parentID: nil,
                categoryID: categoryID,
                colorHex: content.colorHex,
                iconName: content.iconName
            )
            try repository.updateTask(
                taskID: task.id,
                title: task.title,
                parentID: nil,
                categoryID: categoryID,
                colorHex: content.colorHex,
                iconName: content.iconName,
                notes: content.notes,
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
            let checklistItem = ChecklistItem(
                taskID: taskID,
                title: content.title,
                isCompleted: false,
                sortOrder: (existingChecklistItems.map(\.sortOrder).max() ?? 0) + 10,
                deviceID: deviceID
            )
            context.insert(checklistItem)
            context.insert(
                ChecklistItemVisual(
                    checklistItemID: checklistItem.id,
                    iconName: ChecklistVisualSanitizer.sanitizedIcon(content.iconName),
                    colorHex: ChecklistVisualSanitizer.sanitizedColor(content.colorHex),
                    suggestionTitleSnapshot: content.checklistProvenance?.titleSnapshot,
                    suggestionModelID: content.checklistProvenance?.modelID,
                    suggestionGeneratedAt: content.checklistProvenance?.generatedAt,
                    deviceID: deviceID
                )
            )
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
