import Foundation

nonisolated struct TaskQuantityEntryEditorDraft: Equatable, Sendable {
    var amount: Int
    var recordedAt: Date

    var isValid: Bool {
        TaskQuantityPolicy.valueRange.contains(amount) &&
            PersistentDatePolicy.contains(recordedAt)
    }
}

nonisolated struct TaskQuantityEntryEditorRoute:
    Identifiable,
    Equatable,
    Sendable
{
    nonisolated enum Mode: Equatable, Sendable {
        case add(entryID: UUID)
        case edit(
            entryBaseline: TaskQuantityEntryMutationBaseline,
            updateOperationID: UUID,
            deleteOperationID: UUID
        )
    }

    let id: UUID
    let taskID: UUID
    let goalBaseline: TaskQuantityGoalMutationBaseline
    let unitLabel: String
    let initialDraft: TaskQuantityEntryEditorDraft
    let mode: Mode

    static func add(
        detail: TaskQuantityDetailSnapshot,
        now: Date = Date(),
        routeID: UUID = UUID(),
        entryID: UUID = UUID()
    ) -> TaskQuantityEntryEditorRoute {
        let remaining = detail.progress.remainingAmount
        let amount = remaining > 0 ? Int(remaining) : 1
        return TaskQuantityEntryEditorRoute(
            id: routeID,
            taskID: detail.progress.taskID,
            goalBaseline: detail.progress.goalBaseline,
            unitLabel: detail.progress.unitLabel,
            initialDraft: TaskQuantityEntryEditorDraft(
                amount: amount,
                recordedAt: now
            ),
            mode: .add(entryID: entryID)
        )
    }

    static func edit(
        detail: TaskQuantityDetailSnapshot,
        entry: TaskQuantityEntrySnapshot,
        routeID: UUID = UUID(),
        updateOperationID: UUID = UUID(),
        deleteOperationID: UUID = UUID()
    ) -> TaskQuantityEntryEditorRoute {
        TaskQuantityEntryEditorRoute(
            id: routeID,
            taskID: detail.progress.taskID,
            goalBaseline: detail.progress.goalBaseline,
            unitLabel: detail.progress.unitLabel,
            initialDraft: TaskQuantityEntryEditorDraft(
                amount: entry.amount,
                recordedAt: entry.recordedAt
            ),
            mode: .edit(
                entryBaseline: entry.baseline,
                updateOperationID: updateOperationID,
                deleteOperationID: deleteOperationID
            )
        )
    }

    var isEditing: Bool {
        if case .edit = mode {
            return true
        }
        return false
    }
}
