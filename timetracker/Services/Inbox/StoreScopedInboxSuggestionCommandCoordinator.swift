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
                  item.clientMutationID == baseline.clientMutationID
            else {
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
                  )
            else {
                return InboxMutationOutcome(affectedItemIDs: [item.id], didMutate: false)
            }
            guard try isRouteDestinationAvailable(
                result.destination,
                context: context
            ) else {
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
                  item.suggestionIdentity == baseline.itemIdentity
            else {
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
                let destination = suggestion.manualRouteDestination,
                InboxSuggestionStateService().displaySuggestion(
                    for: resolution.readModel,
                    suggestion: suggestion
                ) != nil
            else {
                throw StoreScopedInboxMutationError.inboxChanged
            }

            let appliedAt = nowProvider()
            let preparedItem = try InboxPersistencePolicy.prepareItem(
                title: item.title,
                notes: item.notes,
                suggestionReason: item.suggestionReason
            )
            let preparedSuggestion = try InboxPersistencePolicy.prepareSuggestion(
                reason: suggestion.reason,
                iconName: suggestion.iconName,
                colorHex: suggestion.colorHex,
                modelID: suggestion.modelID,
                titleSnapshot: suggestion.titleSnapshot
            )
            let mutationIDBeforeApply = item.clientMutationID
            let creation = try createRouteDestination(
                destination,
                content: .suggested(
                    item: preparedItem,
                    suggestion: preparedSuggestion,
                    appliedAt: appliedAt
                ),
                context: context
            )
            try handler.softDelete(
                item,
                context: context,
                now: appliedAt,
                deviceID: deviceID
            )
            return InboxManualRouteOutcome(
                inboxItemID: item.id,
                creation: creation,
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
        return try InboxSuggestionIdentityService()
            .visibleLogicalResolutions(from: context.fetch(descriptor))
            .first { $0.winner.effectiveSuggestionContextID == contextID }
    }

    private func isRouteDestinationAvailable(
        _ destination: InboxManualRouteDestination,
        context: ModelContext
    ) throws -> Bool {
        switch destination {
        case let .childTask(parentTaskID):
            try trackableTasks(context: context).trackableIDs.contains(parentTaskID)
        case let .category(categoryID):
            try SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID
            ).category(id: categoryID) != nil
        case let .checklist(taskID):
            try trackableTasks(context: context).trackableIDs.contains(taskID)
        }
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
