import SwiftUI

@MainActor
enum TaskQuantityEntryEditorActions {
    static var allowedDateRange: ClosedRange<Date> {
        let maximumDate = PersistentDatePolicy.maximumDateExclusive.addingTimeInterval(-1)
        return PersistentDatePolicy.minimumDate...maximumDate
    }

    static func validationMessage(
        for draft: TaskQuantityEntryEditorDraft
    ) -> String {
        if TaskQuantityPolicy.valueRange.contains(draft.amount) == false {
            return TaskQuantityEntryMutationError.invalidAmount
                .localizedDescription
        }
        return TaskQuantityEntryMutationError.invalidRecordedAt
            .localizedDescription
    }

    static func save(
        store: TimeTrackerStore,
        route: TaskQuantityEntryEditorRoute,
        draft: TaskQuantityEntryEditorDraft
    ) -> Bool {
        switch route.mode {
        case .add(let entryID):
            return store.recordTaskQuantity(
                taskID: route.taskID,
                goalBaseline: route.goalBaseline,
                amount: draft.amount,
                entryID: entryID,
                recordedAt: draft.recordedAt
            )
        case let .edit(entryBaseline, operationID, _):
            return store.updateTaskQuantityEntry(
                baseline: entryBaseline,
                goalBaseline: route.goalBaseline,
                amount: draft.amount,
                recordedAt: draft.recordedAt,
                operationID: operationID
            )
        }
    }

    static func delete(
        store: TimeTrackerStore,
        route: TaskQuantityEntryEditorRoute
    ) -> Bool {
        guard case let .edit(entryBaseline, _, operationID) = route.mode
        else {
            return false
        }
        return store.deleteTaskQuantityEntry(
            baseline: entryBaseline,
            operationID: operationID
        )
    }
}
