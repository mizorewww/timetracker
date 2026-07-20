import Foundation

extension AppPresentationRouter {
    @discardableResult
    func presentRecoveredTaskDraft(
        _ record: TaskDraftRecoveryRecord,
        using store: TimeTrackerStore,
        preservingDestination: TimeTrackerStore.DesktopDestination = .tasks
    ) -> Bool {
        let parentID = record.draft.parentID.flatMap {
            store.isTaskDetailRouteValid($0) ? $0 : nil
        }
        let categoryID =
            record.draft.parentID == nil && parentID == nil
                ? record.draft.categoryID.flatMap {
                    store.taskCategory(for: $0) == nil ? nil : $0
                }
                : nil
        return present(.recoveredTaskEditor(
            RecoveredTaskDraftPresentation(
                sourceTaskID: record.sourceTaskID,
                proposedTaskID: record.draft.id,
                savedTaskID: store.task(for: record.draft.id)?.id,
                draft: record.draft.copyAsNew(
                    parentID: parentID,
                    categoryID: categoryID
                ),
                returnDestination: preservingDestination
            )
        ))
    }
}
