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
        let preparedSuggestions = try preparedSuggestionMutations(
            for: item.id,
            context: context
        )

        try context.performAtomicMutation {
            preparedItem.apply(to: item)
            item.suggestedTaskID = nil
            item.suggestionGeneratedAt = now
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
            tombstone(preparedSuggestions, now: now, deviceID: deviceID)
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
        let inboxItemID = item.id
        let existing = try context.fetch(
            FetchDescriptor<InboxSuggestion>(
                predicate: #Predicate { $0.inboxItemID == inboxItemID }
            )
        )
            .deduplicatedByID()
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString > rhs.id.uuidString
            }
        let active = existing.first { $0.deletedAt == nil }
        let duplicateMutations = try existing
            .filter { $0.deletedAt == nil && $0.id != active?.id }
            .map(prepareSuggestionMutation)

        try context.performAtomicMutation {
            preparedItem.apply(to: item)
            if let active {
                update(
                    active,
                    taskID: result.taskID,
                    text: preparedResult,
                    now: now,
                    deviceID: deviceID
                )
            } else {
                context.insert(
                    InboxSuggestion(
                        inboxItemID: item.id,
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
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
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
        let nextSortOrder = ((existingChecklistItems.map(\.sortOrder).max() ?? 0) + 10)
        return try context.performAtomicMutation {
            preparedItem.apply(to: item)
            preparedSuggestion.apply(to: suggestion)

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

    private func update(
        _ suggestion: InboxSuggestion,
        taskID: UUID,
        text: PreparedInboxSuggestionText,
        now: Date,
        deviceID: String
    ) {
        text.apply(to: suggestion)
        suggestion.taskID = taskID
        suggestion.generatedAt = now
        suggestion.updatedAt = now
        suggestion.deviceID = deviceID
        suggestion.clientMutationID = UUID()
    }

    func preparedSuggestionMutations(
        for inboxItemID: UUID,
        context: ModelContext
    ) throws -> [PreparedInboxSuggestionMutation] {
        try context.fetch(
            FetchDescriptor<InboxSuggestion>(
                predicate: #Predicate { $0.inboxItemID == inboxItemID }
            )
        )
        .visibleDeduplicatedByID()
        .map(prepareSuggestionMutation)
    }

    func prepareSuggestionMutation(
        _ suggestion: InboxSuggestion
    ) throws -> PreparedInboxSuggestionMutation {
        PreparedInboxSuggestionMutation(
            suggestion: suggestion,
            text: try InboxPersistencePolicy.prepareSuggestion(
                reason: suggestion.reason,
                iconName: suggestion.iconName,
                colorHex: suggestion.colorHex,
                modelID: suggestion.modelID,
                titleSnapshot: suggestion.titleSnapshot
            )
        )
    }

    func tombstone(
        _ preparedSuggestions: [PreparedInboxSuggestionMutation],
        now: Date,
        deviceID: String
    ) {
        for preparedSuggestion in preparedSuggestions {
            preparedSuggestion.text.apply(to: preparedSuggestion.suggestion)
            softDelete(preparedSuggestion.suggestion, now: now, deviceID: deviceID)
        }
    }

    private func softDelete(_ suggestion: InboxSuggestion, now: Date, deviceID: String) {
        suggestion.deletedAt = now
        suggestion.updatedAt = now
        suggestion.deviceID = deviceID
        suggestion.clientMutationID = UUID()
    }
}
