import Foundation
import SwiftData

extension InboxCommandHandler {
    func discardSuggestion(_ item: InboxItem, context: ModelContext, now: Date = Date()) throws {
        item.suggestedTaskID = nil
        item.suggestionReason = nil
        item.suggestionGeneratedAt = now
        item.updatedAt = now
        item.clientMutationID = UUID()
        try clearSuggestions(for: item.id, context: context, now: now)
        try context.save()
    }

    func upsertSuggestion(
        item: InboxItem,
        result: LLMInboxSuggestionResult,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        let inboxItemID = item.id
        let existing = try context.fetch(
            FetchDescriptor<InboxSuggestion>(
                predicate: #Predicate { $0.inboxItemID == inboxItemID },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )
        let active = existing.first { $0.deletedAt == nil }
        if let active {
            update(active, with: result, item: item, now: now)
        } else {
            context.insert(
                InboxSuggestion(
                    inboxItemID: item.id,
                    taskID: result.taskID,
                    reason: result.reason,
                    iconName: result.iconName,
                    colorHex: result.colorHex,
                    modelID: result.modelID,
                    titleSnapshot: item.title,
                    generatedAt: now,
                    deviceID: deviceID
                )
            )
        }

        for suggestion in existing where suggestion.deletedAt == nil && suggestion.id != active?.id {
            softDelete(suggestion, now: now)
        }

        item.suggestedTaskID = result.taskID
        item.suggestionReason = result.reason
        item.suggestionGeneratedAt = now
        item.updatedAt = now
        item.clientMutationID = UUID()
        try context.save()
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
            reason: draft.reason.trimmingCharacters(in: .whitespacesAndNewlines),
            iconName: ChecklistVisualSanitizer.sanitizedIcon(draft.iconName),
            colorHex: ChecklistVisualSanitizer.sanitizedColor(draft.colorHex),
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
        let nextSortOrder = ((existingChecklistItems.map(\.sortOrder).max() ?? 0) + 10)
        let checklistItem = ChecklistItem(
            taskID: suggestion.taskID,
            title: item.title,
            isCompleted: false,
            sortOrder: nextSortOrder,
            deviceID: deviceID
        )
        context.insert(checklistItem)
        context.insert(
            ChecklistItemVisual(
                checklistItemID: checklistItem.id,
                iconName: ChecklistVisualSanitizer.sanitizedIcon(suggestion.iconName),
                colorHex: ChecklistVisualSanitizer.sanitizedColor(suggestion.colorHex),
                suggestionTitleSnapshot: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                suggestionModelID: suggestion.modelID,
                suggestionGeneratedAt: now,
                deviceID: deviceID
            )
        )

        item.deletedAt = now
        item.updatedAt = now
        item.clientMutationID = UUID()
        softDelete(suggestion, now: now)
        try context.save()
        return checklistItem
    }

    func clearSuggestions(for inboxItemID: UUID, context: ModelContext, now: Date) throws {
        let suggestions = try context.fetch(
            FetchDescriptor<InboxSuggestion>(
                predicate: #Predicate { $0.inboxItemID == inboxItemID && $0.deletedAt == nil }
            )
        )
        for suggestion in suggestions {
            softDelete(suggestion, now: now)
        }
    }

    private func update(
        _ suggestion: InboxSuggestion,
        with result: LLMInboxSuggestionResult,
        item: InboxItem,
        now: Date
    ) {
        suggestion.taskID = result.taskID
        suggestion.reason = result.reason
        suggestion.iconName = result.iconName
        suggestion.colorHex = result.colorHex
        suggestion.modelID = result.modelID
        suggestion.titleSnapshot = item.title
        suggestion.generatedAt = now
        suggestion.updatedAt = now
        suggestion.clientMutationID = UUID()
    }

    private func softDelete(_ suggestion: InboxSuggestion, now: Date) {
        suggestion.deletedAt = now
        suggestion.updatedAt = now
        suggestion.clientMutationID = UUID()
    }
}
