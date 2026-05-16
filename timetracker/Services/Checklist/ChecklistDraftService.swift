import Foundation
import SwiftData

@MainActor
struct ChecklistDraftService {
    func save(
        drafts: [ChecklistEditorDraft],
        taskID: UUID,
        context: ModelContext,
        deviceID: String = DeviceIdentity.current
    ) throws {
        let targetTaskID = taskID
        let existing = try context.fetch(
            FetchDescriptor<ChecklistItem>(
                predicate: #Predicate { $0.taskID == targetTaskID },
                sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
            )
        )
        let existingByID = existing.latestByID()
        let existingIDs = Set(existing.map(\.id))
        let requestedItemIDs = Array(existingIDs)
        let visuals = try context.fetch(
            FetchDescriptor<ChecklistItemVisual>(
                predicate: #Predicate { requestedItemIDs.contains($0.checklistItemID) }
            )
        )
        let visualByItemID = Dictionary(grouping: visuals, by: \.checklistItemID)
            .compactMapValues { values in
                values.sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }.first
            }
        var keptIDs = Set<UUID>()
        let now = Date()

        for (index, draft) in drafts.enumerated() {
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let sortOrder = Double(index + 1) * 10
            if let existingID = draft.existingID, let item = existingByID[existingID] {
                item.title = title
                if item.isCompleted != draft.isCompleted {
                    item.completedAt = draft.isCompleted ? Date() : nil
                }
                item.isCompleted = draft.isCompleted
                item.sortOrder = sortOrder
                item.deletedAt = nil
                item.updatedAt = now
                item.clientMutationID = UUID()
                upsertVisual(
                    for: item.id,
                    draft: draft,
                    existing: visualByItemID[item.id],
                    title: title,
                    context: context,
                    now: now,
                    deviceID: deviceID
                )
                keptIDs.insert(item.id)
            } else {
                let item = ChecklistItem(
                    taskID: taskID,
                    title: title,
                    isCompleted: draft.isCompleted,
                    sortOrder: sortOrder,
                    deviceID: deviceID
                )
                context.insert(item)
                context.insert(
                    ChecklistItemVisual(
                        checklistItemID: item.id,
                        iconName: ChecklistVisualSanitizer.sanitizedIcon(draft.iconName),
                        colorHex: ChecklistVisualSanitizer.sanitizedColor(draft.colorHex),
                        userEditedAt: isManualVisual(iconName: draft.iconName, colorHex: draft.colorHex) ? now : nil,
                        deviceID: deviceID
                    )
                )
                keptIDs.insert(item.id)
            }
        }

        for item in existing where item.deletedAt == nil && !keptIDs.contains(item.id) {
            item.deletedAt = now
            item.updatedAt = now
            item.clientMutationID = UUID()
            if let visual = visualByItemID[item.id] {
                visual.deletedAt = now
                visual.updatedAt = now
                visual.clientMutationID = UUID()
            }
        }
        try context.save()
    }

    private func upsertVisual(
        for checklistItemID: UUID,
        draft: ChecklistEditorDraft,
        existing: ChecklistItemVisual?,
        title: String,
        context: ModelContext,
        now: Date,
        deviceID: String
    ) {
        let iconName = ChecklistVisualSanitizer.sanitizedIcon(draft.iconName)
        let colorHex = ChecklistVisualSanitizer.sanitizedColor(draft.colorHex)
        if let existing {
            let visualChanged = ChecklistVisualSanitizer.sanitizedIcon(existing.iconName) != iconName ||
                ChecklistVisualSanitizer.sanitizedColor(existing.colorHex) != colorHex
            existing.iconName = iconName
            existing.colorHex = colorHex
            if visualChanged {
                existing.userEditedAt = now
                existing.suggestionTitleSnapshot = title
                existing.suggestionModelID = "manual"
                existing.suggestionGeneratedAt = nil
            }
            existing.deletedAt = nil
            existing.updatedAt = now
            existing.clientMutationID = UUID()
        } else {
            context.insert(
                ChecklistItemVisual(
                    checklistItemID: checklistItemID,
                    iconName: iconName,
                    colorHex: colorHex,
                    userEditedAt: isManualVisual(iconName: iconName, colorHex: colorHex) ? now : nil,
                    deviceID: deviceID
                )
            )
        }
    }

    private func isManualVisual(iconName: String?, colorHex: String?) -> Bool {
        !ChecklistVisualSanitizer.isDefault(iconName: iconName, colorHex: colorHex)
    }
}
