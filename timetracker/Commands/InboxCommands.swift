import Foundation
import SwiftData

@MainActor
struct InboxCommandHandler {
    @discardableResult
    func add(
        title: String,
        existingItems: [InboxItem],
        context: ModelContext,
        deviceID: String = DeviceIdentity.current
    ) throws -> InboxItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }

        let nextSortOrder = (existingItems.filter { !$0.isCompleted }.map(\.sortOrder).max() ?? 0) + 10
        let item = InboxItem(
            title: trimmedTitle,
            isCompleted: false,
            sortOrder: nextSortOrder,
            deviceID: deviceID
        )
        context.insert(item)
        try context.save()
        return item
    }

    func toggle(_ item: InboxItem, context: ModelContext, now: Date = Date()) throws {
        item.isCompleted.toggle()
        item.completedAt = item.isCompleted ? now : nil
        item.updatedAt = now
        item.clientMutationID = UUID()
        try context.save()
    }

    func updateTitle(_ item: InboxItem, title: String, context: ModelContext, now: Date = Date()) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            try softDelete(item, context: context, now: now)
            return
        }
        guard item.title != trimmedTitle else { return }

        item.title = trimmedTitle
        item.suggestedTaskID = nil
        item.suggestionReason = nil
        item.suggestionGeneratedAt = nil
        item.updatedAt = now
        item.clientMutationID = UUID()
        try clearSuggestions(for: item.id, context: context, now: now)
        try context.save()
    }

    func softDelete(_ item: InboxItem, context: ModelContext, now: Date = Date()) throws {
        item.deletedAt = now
        item.updatedAt = now
        item.clientMutationID = UUID()
        try clearSuggestions(for: item.id, context: context, now: now)
        try context.save()
    }

    func discardSuggestion(_ item: InboxItem, context: ModelContext, now: Date = Date()) throws {
        item.suggestedTaskID = nil
        item.suggestionReason = nil
        item.suggestionGeneratedAt = now
        item.updatedAt = now
        item.clientMutationID = UUID()
        try clearSuggestions(for: item.id, context: context, now: now)
        try context.save()
    }

    func reorderedOpenItemIDs(
        items: [InboxItem],
        sourceOffsets: IndexSet,
        destination: Int
    ) -> [UUID] {
        let ids = items.map(\.id)
        guard !sourceOffsets.isEmpty else { return ids }

        let moving = sourceOffsets.sorted().compactMap { index in
            ids.indices.contains(index) ? ids[index] : nil
        }
        let sourceSet = Set(sourceOffsets)
        var remaining = ids.enumerated()
            .filter { !sourceSet.contains($0.offset) }
            .map(\.element)
        let adjustedDestination = destination - sourceOffsets.filter { $0 < destination }.count
        let clampedDestination = min(max(0, adjustedDestination), remaining.count)
        remaining.insert(contentsOf: moving, at: clampedDestination)
        return remaining
    }

    func reorderOpenItems(
        orderedItemIDs: [UUID],
        context: ModelContext,
        now: Date = Date()
    ) throws {
        guard !orderedItemIDs.isEmpty else { return }
        let items = try context.fetch(
            FetchDescriptor<InboxItem>(
                predicate: #Predicate { $0.deletedAt == nil && $0.isCompleted == false }
            )
        )
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        guard orderedItemIDs.count == items.count else { return }

        for (index, itemID) in orderedItemIDs.enumerated() {
            guard let item = itemByID[itemID] else { return }
            item.sortOrder = Double(index + 1) * 10
            item.updatedAt = now
            item.clientMutationID = UUID()
        }
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
            active.taskID = result.taskID
            active.reason = result.reason
            active.iconName = result.iconName
            active.colorHex = result.colorHex
            active.modelID = result.modelID
            active.titleSnapshot = item.title
            active.generatedAt = now
            active.updatedAt = now
            active.clientMutationID = UUID()
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
            suggestion.deletedAt = now
            suggestion.updatedAt = now
            suggestion.clientMutationID = UUID()
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
        suggestion.deletedAt = now
        suggestion.updatedAt = now
        suggestion.clientMutationID = UUID()
        try context.save()
        return checklistItem
    }

    private func clearSuggestions(for inboxItemID: UUID, context: ModelContext, now: Date) throws {
        let suggestions = try context.fetch(
            FetchDescriptor<InboxSuggestion>(
                predicate: #Predicate { $0.inboxItemID == inboxItemID && $0.deletedAt == nil }
            )
        )
        for suggestion in suggestions {
            suggestion.deletedAt = now
            suggestion.updatedAt = now
            suggestion.clientMutationID = UUID()
        }
    }
}
