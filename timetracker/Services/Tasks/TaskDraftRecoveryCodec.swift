import Foundation

nonisolated struct TaskDraftRecoveryEnvelope: Codable, Sendable {
    let schemaVersion: Int
    let sourceTaskID: UUID
    let savedAt: Date
    let draft: TaskEditorDraft
}

nonisolated enum TaskDraftRecoveryCodec {
    static func encode(
        _ envelope: TaskDraftRecoveryEnvelope
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }

    static func decode(
        _ data: Data
    ) throws -> TaskDraftRecoveryEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(
            TaskDraftRecoveryEnvelope.self,
            from: data
        )
    }

    static func hasSameRecoverableContent(
        _ lhs: TaskEditorDraft,
        _ rhs: TaskEditorDraft
    ) -> Bool {
        lhs.taskID == rhs.taskID &&
            lhs.title == rhs.title &&
            lhs.parentID == rhs.parentID &&
            lhs.categoryID == rhs.categoryID &&
            lhs.colorHex == rhs.colorHex &&
            lhs.iconName == rhs.iconName &&
            lhs.notes == rhs.notes &&
            lhs.estimatedMinutes == rhs.estimatedMinutes &&
            lhs.hasDueDate == rhs.hasDueDate &&
            (lhs.hasDueDate == false || lhs.dueAt == rhs.dueAt) &&
            lhs.quantityGoal == rhs.quantityGoal &&
            lhs.dailyRecurrence == rhs.dailyRecurrence &&
            hasSameChecklistContent(
                lhs.checklistItems,
                rhs.checklistItems
            )
    }

    private static func hasSameChecklistContent(
        _ lhs: [ChecklistEditorDraft],
        _ rhs: [ChecklistEditorDraft]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { pair in
            let (lhsItem, rhsItem) = pair
            return lhsItem.title == rhsItem.title &&
                lhsItem.isCompleted == rhsItem.isCompleted &&
                lhsItem.iconName == rhsItem.iconName &&
                lhsItem.colorHex == rhsItem.colorHex
        }
    }
}
