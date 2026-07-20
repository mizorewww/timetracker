import Foundation
import SwiftData

extension InboxCommandHandler {
    func discardSuggestion(
        _ item: InboxItem,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        let logicalMutation = try preparedLogicalMutation(for: item, context: context)
        let winner = logicalMutation.winner.item
        guard winner.deletedAt == nil,
              winner.suggestionIdentity == item.suggestionIdentity else { return }
        let preparedItem = try InboxPersistencePolicy.prepareItem(
            title: winner.title,
            notes: winner.notes,
            suggestionReason: nil
        )
        let preparedSuggestions = try preparedSuggestionMutations(for: winner, context: context)

        try context.performAtomicMutation {
            winner.materializeSuggestionIdentity()
            preparedItem.apply(to: winner)
            winner.suggestedTaskID = nil
            winner.suggestionGeneratedAt = now
            winner.dismissedSuggestionRevisionID = winner.effectiveSuggestionRevisionID
            winner.updatedAt = now
            winner.deviceID = deviceID
            winner.clientMutationID = UUID()
            tombstone(preparedSuggestions, now: now, deviceID: deviceID)
            tombstoneSuperseded(
                logicalMutation.activeSiblings,
                winnerUpdatedAt: now,
                deviceID: deviceID
            )
        }
    }

    func upsertSuggestion(
        item: InboxItem,
        result: LLMInboxSuggestionResult,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        let logicalMutation = try preparedLogicalMutation(for: item, context: context)
        let winner = logicalMutation.winner.item
        guard winner.deletedAt == nil,
              winner.suggestionIdentity == item.suggestionIdentity else { return }
        let preparedItem = try InboxPersistencePolicy.prepareItem(
            title: winner.title,
            notes: winner.notes,
            suggestionReason: result.reason
        )
        let preparedResult = try InboxPersistencePolicy.prepareSuggestion(
            reason: result.reason,
            iconName: result.iconName,
            colorHex: result.colorHex,
            modelID: result.modelID,
            titleSnapshot: preparedItem.title
        )
        let existing = try suggestions(for: winner, context: context)
            .deduplicatedByID()
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString > rhs.id.uuidString
            }
        let identity = winner.suggestionIdentity
        let active = existing.first {
            $0.deletedAt == nil &&
                ($0.explicitInboxItemIdentity == identity ||
                    ($0.explicitInboxItemIdentity == nil && $0.inboxItemID == winner.id))
        }
        let duplicateMutations = try existing
            .filter { $0.deletedAt == nil && $0.id != active?.id }
            .map(prepareSuggestionMutation)
        try context.performAtomicMutation {
            winner.materializeSuggestionIdentity()
            preparedItem.apply(to: winner)
            if let active {
                update(
                    active,
                    item: winner,
                    destination: result.destination,
                    text: preparedResult,
                    now: now,
                    deviceID: deviceID
                )
            } else {
                context.insert(
                    InboxSuggestion(
                        inboxItemID: winner.id,
                        inboxItemContextID: winner.effectiveSuggestionContextID,
                        inboxItemRevisionID: winner.effectiveSuggestionRevisionID,
                        taskID: result.destination.persistenceTargetID,
                        destinationKind: result.destination.suggestionDestinationKind,
                        reason: preparedResult.reason,
                        iconName: preparedResult.iconName,
                        colorHex: preparedResult.colorHex,
                        modelID: preparedResult.modelID,
                        titleSnapshot: preparedResult.titleSnapshot,
                        generatedAt: now,
                        deviceID: deviceID
                    )
                )
            }

            tombstone(duplicateMutations, now: now, deviceID: deviceID)

            winner.suggestedTaskID = result.destination.legacySuggestedTaskID
            winner.suggestionGeneratedAt = now
            winner.dismissedSuggestionRevisionID = nil
            winner.updatedAt = now
            winner.deviceID = deviceID
            winner.clientMutationID = UUID()
            tombstoneSuperseded(
                logicalMutation.activeSiblings,
                winnerUpdatedAt: now,
                deviceID: deviceID
            )
        }
    }

    func saveSuggestionDraft(
        item: InboxItem,
        draft: InboxSuggestionEditorDraft,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        guard let taskID = draft.taskID else { return }
        let result = LLMInboxSuggestionResult(
            destination: .checklist(taskID: taskID),
            reason: draft.reason,
            iconName: draft.iconName,
            colorHex: draft.colorHex,
            modelID: "manual"
        )
        try upsertSuggestion(item: item, result: result, context: context, now: now, deviceID: deviceID)
    }

    @discardableResult
    func applySuggestion(
        item: InboxItem,
        suggestion: InboxSuggestion,
        existingChecklistItems: [ChecklistItem],
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws -> ChecklistItem {
        let logicalMutation = try preparedLogicalMutation(for: item, context: context)
        let winner = logicalMutation.winner.item
        guard winner.deletedAt == nil,
              winner.suggestionIdentity == item.suggestionIdentity,
              logicalMutation.mergedDismissedSuggestionRevisionID == nil,
              InboxSuggestionStateService().displaySuggestion(
                  for: winner,
                  suggestion: suggestion
              ) != nil else {
            throw InboxCommandIdentityError.staleSuggestion
        }
        let fetchedSuggestions = try suggestions(for: winner, context: context)
        guard let canonicalSuggestion = InboxSuggestionIdentityService().index(
            items: [winner],
            suggestions: fetchedSuggestions
        )[winner.id],
              canonicalSuggestion.id == suggestion.id,
              canonicalSuggestion.destinationKind == .checklist,
              InboxSuggestionStateService().displaySuggestion(
                  for: winner,
                  suggestion: canonicalSuggestion
              ) != nil else {
            throw InboxCommandIdentityError.staleSuggestion
        }
        let preparedItem = try InboxPersistencePolicy.prepareItem(
            title: winner.title,
            notes: winner.notes,
            suggestionReason: winner.suggestionReason
        )
        let preparedSuggestion = try InboxPersistencePolicy.prepareSuggestion(
            reason: canonicalSuggestion.reason,
            iconName: canonicalSuggestion.iconName,
            colorHex: canonicalSuggestion.colorHex,
            modelID: canonicalSuggestion.modelID,
            titleSnapshot: canonicalSuggestion.titleSnapshot
        )
        let otherSuggestionMutations = try fetchedSuggestions
            .deduplicatedByID()
            .filter { $0.id != canonicalSuggestion.id }
            .map(prepareSuggestionMutation)
        let nextSortOrder = ((existingChecklistItems.map(\.sortOrder).max() ?? 0) + 10)
        return try context.performAtomicMutation {
            winner.materializeSuggestionIdentity()
            logicalMutation.materializeDismissal()
            preparedItem.apply(to: winner)
            preparedSuggestion.apply(to: canonicalSuggestion)
            canonicalSuggestion.inboxItemContextID = winner.effectiveSuggestionContextID
            canonicalSuggestion.inboxItemRevisionID = winner.effectiveSuggestionRevisionID

            let checklistItem = ChecklistItem(
                taskID: canonicalSuggestion.taskID,
                title: preparedItem.title,
                isCompleted: false,
                sortOrder: nextSortOrder,
                deviceID: deviceID
            )
            context.insert(checklistItem)
            context.insert(
                ChecklistItemVisual(
                    checklistItemID: checklistItem.id,
                    iconName: preparedSuggestion.iconName,
                    colorHex: preparedSuggestion.colorHex,
                    suggestionTitleSnapshot: preparedItem.title,
                    suggestionModelID: preparedSuggestion.modelID,
                    suggestionGeneratedAt: now,
                    deviceID: deviceID
                )
            )

            winner.deletedAt = now
            winner.updatedAt = now
            winner.deviceID = deviceID
            winner.clientMutationID = UUID()
            softDelete(canonicalSuggestion, now: now, deviceID: deviceID)
            tombstone(otherSuggestionMutations, now: now, deviceID: deviceID)
            tombstone(logicalMutation.activeSiblings, now: now, deviceID: deviceID)
            return checklistItem
        }
    }

    func clearSuggestions(
        for inboxItemID: UUID,
        context: ModelContext,
        now: Date,
        deviceID: String = DeviceIdentity.current
    ) throws {
        let preparedSuggestions = try preparedSuggestionMutations(
            for: inboxItemID,
            context: context
        )
        guard !preparedSuggestions.isEmpty else { return }
        try context.performAtomicMutation {
            tombstone(preparedSuggestions, now: now, deviceID: deviceID)
        }
    }

}
