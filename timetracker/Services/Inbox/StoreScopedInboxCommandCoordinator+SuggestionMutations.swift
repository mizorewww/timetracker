import Foundation
import SwiftData

extension StoreScopedInboxCommandCoordinator {
    func discardSuggestion(
        _ item: InboxItem,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String
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

        winner.materializeSuggestionIdentity()
        preparedItem.apply(to: winner)
        winner.suggestedTaskID = nil
        winner.suggestionGeneratedAt = now
        winner.dismissedSuggestionRevisionID = winner.effectiveSuggestionRevisionID
        winner.markMutated(at: now, deviceID: deviceID)
        tombstone(preparedSuggestions, now: now, deviceID: deviceID)
        tombstoneSuperseded(
            logicalMutation.activeSiblings,
            winnerUpdatedAt: now,
            deviceID: deviceID
        )
    }

    func upsertSuggestion(
        item: InboxItem,
        result: LLMInboxSuggestionResult,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String
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
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id > rhs.id
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
        winner.markMutated(at: now, deviceID: deviceID)
        tombstoneSuperseded(
            logicalMutation.activeSiblings,
            winnerUpdatedAt: now,
            deviceID: deviceID
        )
    }

    func saveSuggestionDraft(
        item: InboxItem,
        draft: InboxSuggestionEditorDraft,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String
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
}
