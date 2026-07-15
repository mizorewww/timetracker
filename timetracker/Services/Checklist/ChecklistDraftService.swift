import Foundation
import SwiftData

nonisolated enum ChecklistDraftField: Equatable {
    case title
    case iconName
    case colorHex

    var localizationKey: String {
        switch self {
        case .title:
            "checklist.draft.field.title"
        case .iconName:
            "checklist.draft.field.icon"
        case .colorHex:
            "checklist.draft.field.color"
        }
    }
}

enum ChecklistDraftValidationError: LocalizedError, Equatable {
    case emptyTitle(index: Int)
    case controlCharacter(index: Int, field: ChecklistDraftField)
    case byteLimitExceeded(index: Int, field: ChecklistDraftField, actual: Int, maximum: Int)

    var errorDescription: String? {
        switch self {
        case let .emptyTitle(index):
            String(
                format: AppStrings.localized("checklist.draft.error.titleRequiredFormat"),
                index + 1
            )
        case let .controlCharacter(index, field):
            String(
                format: AppStrings.localized("checklist.draft.error.controlCharacterFormat"),
                index + 1,
                AppStrings.localized(field.localizationKey)
            )
        case let .byteLimitExceeded(index, field, _, _):
            String(
                format: AppStrings.localized("checklist.draft.error.tooLongFormat"),
                index + 1,
                AppStrings.localized(field.localizationKey)
            )
        }
    }
}

enum ChecklistDraftPersistencePolicy {
    static let maximumTitleByteCount = SyncDataSnapshotRestoreLimits.maximumTitleByteCount
    static let maximumIconNameByteCount = SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount
    static let maximumColorHexByteCount = SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount

    static func prepare(_ drafts: [ChecklistEditorDraft]) throws -> [PreparedChecklistDraft] {
        try drafts.enumerated().map { index, draft in
            try prepare(draft, index: index)
        }
    }

    private static func prepare(_ draft: ChecklistEditorDraft, index: Int) throws -> PreparedChecklistDraft {
        try rejectControlCharacters(in: draft.title, index: index, field: .title)
        try rejectControlCharacters(in: draft.iconName, index: index, field: .iconName)
        try rejectControlCharacters(in: draft.colorHex, index: index, field: .colorHex)

        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw ChecklistDraftValidationError.emptyTitle(index: index)
        }
        try enforceByteLimit(
            title,
            maximum: maximumTitleByteCount,
            index: index,
            field: .title
        )
        try enforceByteLimit(
            draft.iconName,
            maximum: maximumIconNameByteCount,
            index: index,
            field: .iconName
        )
        try enforceByteLimit(
            draft.colorHex,
            maximum: maximumColorHexByteCount,
            index: index,
            field: .colorHex
        )

        return PreparedChecklistDraft(
            existingID: draft.existingID,
            title: title,
            isCompleted: draft.isCompleted,
            iconName: ChecklistVisualSanitizer.sanitizedIcon(draft.iconName),
            colorHex: ChecklistVisualSanitizer.sanitizedColor(draft.colorHex)
        )
    }

    private static func rejectControlCharacters(
        in value: String,
        index: Int,
        field: ChecklistDraftField
    ) throws {
        guard !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ChecklistDraftValidationError.controlCharacter(index: index, field: field)
        }
    }

    private static func enforceByteLimit(
        _ value: String,
        maximum: Int,
        index: Int,
        field: ChecklistDraftField
    ) throws {
        let actual = value.utf8.count
        guard actual <= maximum else {
            throw ChecklistDraftValidationError.byteLimitExceeded(
                index: index,
                field: field,
                actual: actual,
                maximum: maximum
            )
        }
    }
}

struct PreparedChecklistDraft {
    let existingID: UUID?
    let title: String
    let isCompleted: Bool
    let iconName: String
    let colorHex: String
}

@MainActor
struct ChecklistDraftService {
    func save(
        drafts: [ChecklistEditorDraft],
        taskID: UUID,
        context: ModelContext,
        deviceID: String = DeviceIdentity.current
    ) throws {
        let preparedDrafts = try ChecklistDraftPersistencePolicy.prepare(drafts)
        try context.performAtomicMutation {
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

            for (index, draft) in preparedDrafts.enumerated() {
                let sortOrder = Double(index + 1) * 10
                if let existingID = draft.existingID, let item = existingByID[existingID] {
                    item.title = draft.title
                    if item.isCompleted != draft.isCompleted {
                        item.completedAt = draft.isCompleted ? now : nil
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
                        context: context,
                        now: now,
                        deviceID: deviceID
                    )
                    keptIDs.insert(item.id)
                } else {
                    let item = ChecklistItem(
                        taskID: taskID,
                        title: draft.title,
                        isCompleted: draft.isCompleted,
                        sortOrder: sortOrder,
                        deviceID: deviceID
                    )
                    context.insert(item)
                    context.insert(
                        ChecklistItemVisual(
                            checklistItemID: item.id,
                            iconName: draft.iconName,
                            colorHex: draft.colorHex,
                            userEditedAt: isManualVisual(
                                iconName: draft.iconName,
                                colorHex: draft.colorHex
                            ) ? now : nil,
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
        }
    }

    private func upsertVisual(
        for checklistItemID: UUID,
        draft: PreparedChecklistDraft,
        existing: ChecklistItemVisual?,
        context: ModelContext,
        now: Date,
        deviceID: String
    ) {
        if let existing {
            let visualChanged = ChecklistVisualSanitizer.sanitizedIcon(existing.iconName) != draft.iconName ||
                ChecklistVisualSanitizer.sanitizedColor(existing.colorHex) != draft.colorHex
            existing.iconName = draft.iconName
            existing.colorHex = draft.colorHex
            if visualChanged {
                existing.userEditedAt = now
                existing.suggestionTitleSnapshot = draft.title
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
                    iconName: draft.iconName,
                    colorHex: draft.colorHex,
                    userEditedAt: isManualVisual(
                        iconName: draft.iconName,
                        colorHex: draft.colorHex
                    ) ? now : nil,
                    deviceID: deviceID
                )
            )
        }
    }

    private func isManualVisual(iconName: String?, colorHex: String?) -> Bool {
        !ChecklistVisualSanitizer.isDefault(iconName: iconName, colorHex: colorHex)
    }
}
