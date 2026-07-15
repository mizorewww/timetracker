import Foundation
import SwiftData

extension InboxCommandHandler {
    func discardSuggestion(
        _ item: InboxItem,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        let preparedItem = try InboxPersistencePolicy.prepareItem(
            title: item.title,
            notes: item.notes,
            suggestionReason: nil
        )
        let preparedSuggestions = try preparedSuggestionMutations(for: item, context: context)
        let preparedSiblings = try preparedLogicalSiblingMutations(for: item, context: context)

        try context.performAtomicMutation {
            item.materializeSuggestionIdentity()
            preparedItem.apply(to: item)
            item.suggestedTaskID = nil
            item.suggestionGeneratedAt = now
            item.dismissedSuggestionRevisionID = item.effectiveSuggestionRevisionID
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
            tombstone(preparedSuggestions, now: now, deviceID: deviceID)
            tombstoneSuperseded(preparedSiblings, winnerUpdatedAt: now, deviceID: deviceID)
        }
    }

    func upsertSuggestion(
        item: InboxItem,
        result: LLMInboxSuggestionResult,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        let preparedItem = try InboxPersistencePolicy.prepareItem(
            title: item.title,
            notes: item.notes,
            suggestionReason: result.reason
        )
        let preparedResult = try InboxPersistencePolicy.prepareSuggestion(
            reason: result.reason,
            iconName: result.iconName,
            colorHex: result.colorHex,
            modelID: result.modelID,
            titleSnapshot: preparedItem.title
        )
        let existing = try suggestions(for: item, context: context)
            .deduplicatedByID()
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString > rhs.id.uuidString
            }
        let identity = item.suggestionIdentity
        let active = existing.first {
            $0.deletedAt == nil &&
                ($0.explicitInboxItemIdentity == identity ||
                    ($0.explicitInboxItemIdentity == nil && $0.inboxItemID == item.id))
        }
        let duplicateMutations = try existing
            .filter { $0.deletedAt == nil && $0.id != active?.id }
            .map(prepareSuggestionMutation)
        let preparedSiblings = try preparedLogicalSiblingMutations(for: item, context: context)

        try context.performAtomicMutation {
            item.materializeSuggestionIdentity()
            preparedItem.apply(to: item)
            if let active {
                update(
                    active,
                    item: item,
                    taskID: result.taskID,
                    text: preparedResult,
                    now: now,
                    deviceID: deviceID
                )
            } else {
                context.insert(
                    InboxSuggestion(
                        inboxItemID: item.id,
                        inboxItemContextID: item.effectiveSuggestionContextID,
                        inboxItemRevisionID: item.effectiveSuggestionRevisionID,
                        taskID: result.taskID,
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

            item.suggestedTaskID = result.taskID
            item.suggestionGeneratedAt = now
            item.dismissedSuggestionRevisionID = nil
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
            tombstoneSuperseded(preparedSiblings, winnerUpdatedAt: now, deviceID: deviceID)
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
            taskID: taskID,
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
        let otherSuggestionMutations = try preparedSuggestionMutations(for: item, context: context)
            .filter { $0.suggestion.id != suggestion.id }
        let preparedSiblings = try preparedLogicalSiblingMutations(for: item, context: context)
        let nextSortOrder = ((existingChecklistItems.map(\.sortOrder).max() ?? 0) + 10)
        return try context.performAtomicMutation {
            item.materializeSuggestionIdentity()
            preparedItem.apply(to: item)
            preparedSuggestion.apply(to: suggestion)
            suggestion.inboxItemContextID = item.effectiveSuggestionContextID
            suggestion.inboxItemRevisionID = item.effectiveSuggestionRevisionID

            let checklistItem = ChecklistItem(
                taskID: suggestion.taskID,
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

            item.deletedAt = now
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
            softDelete(suggestion, now: now, deviceID: deviceID)
            tombstone(otherSuggestionMutations, now: now, deviceID: deviceID)
            tombstone(preparedSiblings, now: now, deviceID: deviceID)
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
