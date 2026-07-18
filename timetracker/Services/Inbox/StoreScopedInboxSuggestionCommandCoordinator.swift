import Foundation
import SwiftData

struct InboxSuggestionApplyBaseline: Equatable, Sendable {
    let itemID: UUID
    let itemMutationID: UUID
    let itemIdentity: InboxSuggestionIdentity
    let suggestionID: UUID
    let suggestionMutationID: UUID

    init(item: InboxItem, suggestion: InboxSuggestion) {
        itemID = item.id
        itemMutationID = item.clientMutationID
        itemIdentity = item.suggestionIdentity
        suggestionID = suggestion.id
        suggestionMutationID = suggestion.clientMutationID
    }
}

struct InboxChecklistRouteOutcome: Equatable {
    let inboxItemID: UUID
    let checklistItemID: UUID
    let taskID: UUID
    let affectedAncestorIDs: Set<UUID>
    let didMutate: Bool

    var events: Set<StoreDomainEvent> {
        guard didMutate else { return [] }
        return [
            .inboxChanged(itemIDs: [inboxItemID]),
            .checklistChanged(
                taskID: taskID,
                affectedAncestorIDs: affectedAncestorIDs
            ),
        ]
    }
}

extension StoreScopedInboxCommandCoordinator {
    func saveSuggestionDraft(
        baseline: InboxItemMutationBaseline,
        draft: InboxSuggestionEditorDraft
    ) throws -> InboxMutationOutcome {
        guard let taskID = draft.taskID else {
            throw StoreScopedInboxMutationError.taskUnavailable
        }

        return try withFreshLockedContext { context in
            guard let item = try visibleItem(id: baseline.itemID, context: context),
                  item.clientMutationID == baseline.clientMutationID else {
                throw StoreScopedInboxMutationError.inboxChanged
            }
            try requireTrackableTask(taskID, context: context)

            let mutationIDBeforeSave = item.clientMutationID
            try InboxCommandHandler().saveSuggestionDraft(
                item: item,
                draft: draft,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
            return InboxMutationOutcome(
                affectedItemIDs: [item.id],
                didMutate: item.clientMutationID != mutationIDBeforeSave
            )
        }
    }

    /// Drops outdated LLM responses without surfacing an error. A response is
    /// still valid after a pure reorder, but never after a title/revision,
    /// dismissal, completion, deletion, or task-availability change.
    func storeGeneratedSuggestion(
        itemID: UUID,
        requestedTitle: String,
        requestedIdentity: InboxSuggestionIdentity,
        result: LLMInboxSuggestionResult
    ) throws -> InboxMutationOutcome {
        try withFreshLockedContext { context in
            guard let resolution = try visibleLogicalResolution(
                contextID: requestedIdentity.contextID,
                context: context
            ) else {
                return InboxMutationOutcome(affectedItemIDs: [itemID], didMutate: false)
            }

            let item = resolution.winner
            let handler = InboxCommandHandler()
            let suggestions = try handler.suggestions(for: item, context: context)
            let suggestion = InboxSuggestionIdentityService().index(
                items: [item],
                suggestions: suggestions
            )[item.id]
            guard item.suggestionIdentity == requestedIdentity,
                  InboxSuggestionStateService().canStoreGeneratedSuggestion(
                      readModel: resolution.readModel,
                      requestedTitle: requestedTitle,
                      requestedIdentity: requestedIdentity,
                      currentSuggestion: suggestion
                  ) else {
                return InboxMutationOutcome(affectedItemIDs: [item.id], didMutate: false)
            }
            guard try isTrackableTask(result.taskID, context: context) else {
                return InboxMutationOutcome(affectedItemIDs: [item.id], didMutate: false)
            }

            let mutationIDBeforeSave = item.clientMutationID
            try handler.upsertSuggestion(
                item: item,
                result: result,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
            return InboxMutationOutcome(
                affectedItemIDs: [item.id],
                didMutate: item.clientMutationID != mutationIDBeforeSave
            )
        }
    }

    func applySuggestion(
        baseline: InboxSuggestionApplyBaseline
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
                  item.suggestionIdentity == baseline.itemIdentity else {
                throw StoreScopedInboxMutationError.inboxChanged
            }

            let handler = InboxCommandHandler()
            let suggestions = try handler.suggestions(for: item, context: context)
            guard let suggestion = InboxSuggestionIdentityService().index(
                items: [item],
                suggestions: suggestions
            )[item.id],
            suggestion.id == baseline.suggestionID,
            suggestion.clientMutationID == baseline.suggestionMutationID,
            InboxSuggestionStateService().displaySuggestion(
                for: resolution.readModel,
                suggestion: suggestion
            ) != nil else {
                throw StoreScopedInboxMutationError.inboxChanged
            }

            let tasks = try trackableTasks(context: context)
            guard tasks.trackableIDs.contains(suggestion.taskID) else {
                throw StoreScopedInboxMutationError.taskUnavailable
            }
            let existingChecklistItems = try visibleChecklistItems(
                taskID: suggestion.taskID,
                context: context
            )
            let mutationIDBeforeApply = item.clientMutationID
            let checklistItem = try handler.applySuggestion(
                item: item,
                suggestion: suggestion,
                existingChecklistItems: existingChecklistItems,
                context: context,
                now: nowProvider(),
                deviceID: deviceID
            )
            let affectedAncestorIDs = Set(
                StoreSelectionCoordinator().ancestorTaskIDs(
                    for: suggestion.taskID,
                    taskByID: tasks.byID
                )
            )
            return InboxChecklistRouteOutcome(
                inboxItemID: item.id,
                checklistItemID: checklistItem.id,
                taskID: suggestion.taskID,
                affectedAncestorIDs: affectedAncestorIDs,
                didMutate: item.clientMutationID != mutationIDBeforeApply
            )
        }
    }

    func visibleLogicalResolution(
        contextID: UUID,
        context: ModelContext
    ) throws -> InboxItemMergeResolution? {
        let descriptor = FetchDescriptor<InboxItem>(
            predicate: #Predicate {
                $0.id == contextID || $0.suggestionContextID == contextID
            }
        )
        return InboxSuggestionIdentityService()
            .visibleLogicalResolutions(from: try context.fetch(descriptor))
            .first { $0.winner.effectiveSuggestionContextID == contextID }
    }

    private func isTrackableTask(_ taskID: UUID, context: ModelContext) throws -> Bool {
        try trackableTasks(context: context).trackableIDs.contains(taskID)
    }

    private func requireTrackableTask(_ taskID: UUID, context: ModelContext) throws {
        guard try trackableTasks(context: context).trackableIDs.contains(taskID) else {
            throw StoreScopedInboxMutationError.taskUnavailable
        }
    }

    func trackableTasks(
        context: ModelContext
    ) throws -> (trackableIDs: Set<UUID>, byID: [UUID: TaskNode]) {
        let tasks = try SwiftDataTaskRepository(
            context: context,
            deviceID: deviceID
        ).allNodes()
        return (
            TaskTrackingAvailabilityService().trackableTaskIDs(tasks: tasks),
            tasks.reduce(into: [:]) { $0[$1.id] = $1 }
        )
    }

    func visibleChecklistItems(
        taskID: UUID,
        context: ModelContext
    ) throws -> [ChecklistItem] {
        let requestedTaskID = taskID
        return try context.fetch(
            FetchDescriptor<ChecklistItem>(
                predicate: #Predicate { $0.taskID == requestedTaskID }
            )
        ).visibleDeduplicatedByID()
    }
}
