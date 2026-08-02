import Foundation
import SwiftData

@MainActor
struct ChecklistCommandHandler {
    private let orderingService = ChecklistOrderingService()

    @discardableResult
    func add(
        taskID: UUID,
        title: String,
        existingItems: [ChecklistItem],
        context: ModelContext,
        iconName: String = ChecklistVisualSanitizer.defaultIcon,
        colorHex: String = ChecklistVisualSanitizer.defaultColor,
        deviceID: String = DeviceIdentity.current
    ) throws -> ChecklistItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTitle.isEmpty == false else { return nil }

        let nextSortOrder = ((existingItems.map(\.sortOrder).max() ?? 0) + 10)
        let item = ChecklistItem(
            taskID: taskID,
            title: trimmedTitle,
            isCompleted: false,
            sortOrder: nextSortOrder,
            deviceID: deviceID
        )
        context.insert(item)
        context.insert(
            ChecklistItemVisual(
                checklistItemID: item.id,
                iconName: ChecklistVisualSanitizer.sanitizedIcon(iconName),
                colorHex: ChecklistVisualSanitizer.sanitizedColor(colorHex),
                deviceID: deviceID
            )
        )
        try context.saveAfterMutationStep()
        return item
    }

    func toggle(
        _ item: ChecklistItem,
        existingItems: [ChecklistItem],
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        try setCompletion(
            item,
            isCompleted: !item.isCompleted,
            existingItems: existingItems,
            context: context,
            now: now,
            deviceID: deviceID
        )
    }

    func setCompletion(
        _ item: ChecklistItem,
        isCompleted: Bool,
        existingItems: [ChecklistItem],
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        guard item.isCompleted != isCompleted else { return }
        if isCompleted {
            item.sortOrderBeforeCompletion = item.sortOrder
        }
        if let restoredOrder = isCompleted ? nil : item.sortOrderBeforeCompletion {
            item.sortOrder = restoredOrder
            item.sortOrderBeforeCompletion = nil
        } else if let lastSiblingSortOrder = existingItems.lazy
            .filter({ $0.id != item.id && $0.taskID == item.taskID })
            .map(\.sortOrder)
            .max()
        {
            item.sortOrder = lastSiblingSortOrder + 10
        }
        item.isCompleted = isCompleted
        item.completedAt = isCompleted ? now : nil
        item.updatedAt = now
        item.deviceID = deviceID
        item.clientMutationID = UUID()
        try context.saveAfterMutationStep()
    }

    func reorder(
        orderedItemIDs: [UUID],
        existingItems: [ChecklistItem],
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        let items = existingItems.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        let itemByID = items.latestByID()
        let orderedItems = orderedItemIDs.compactMap { itemByID[$0] }
        guard orderedItems.count == items.count else { return }

        for (index, item) in orderedItems.enumerated() {
            item.sortOrder = Double(index + 1) * 10
            item.updatedAt = now
            item.deviceID = deviceID
            item.clientMutationID = UUID()
        }
        try context.saveAfterMutationStep()
    }

    func reorderedIDs(
        items: [ChecklistItem],
        sourceOffsets: IndexSet,
        destination: Int
    ) -> [UUID]? {
        orderingService.reorderedIDs(
            elements: items.map {
                ChecklistOrderingElement(id: $0.id, isCompleted: $0.isCompleted)
            },
            sourceOffsets: sourceOffsets,
            destination: destination
        )
    }

    func applyVisualSuggestion(
        item: ChecklistItem,
        result: LLMChecklistVisualSuggestionResult,
        existingVisual: ChecklistItemVisual?,
        context: ModelContext,
        now: Date = Date(),
        deviceID: String = DeviceIdentity.current
    ) throws {
        let titleSnapshot = ChecklistVisualSuggestionPolicy().normalizedTitle(item.title)
        let iconName = ChecklistVisualSanitizer.sanitizedIcon(result.iconName)
        let colorHex = ChecklistVisualSanitizer.sanitizedColor(result.colorHex)
        if let existingVisual {
            existingVisual.iconName = iconName
            existingVisual.colorHex = colorHex
            existingVisual.suggestionTitleSnapshot = titleSnapshot
            existingVisual.suggestionModelID = result.modelID
            existingVisual.suggestionGeneratedAt = now
            existingVisual.userEditedAt = nil
            existingVisual.deletedAt = nil
            existingVisual.updatedAt = now
            existingVisual.deviceID = deviceID
            existingVisual.clientMutationID = UUID()
        } else {
            context.insert(
                ChecklistItemVisual(
                    checklistItemID: item.id,
                    iconName: iconName,
                    colorHex: colorHex,
                    suggestionTitleSnapshot: titleSnapshot,
                    suggestionModelID: result.modelID,
                    suggestionGeneratedAt: now,
                    deviceID: deviceID
                )
            )
        }
        try context.saveAfterMutationStep()
    }
}
