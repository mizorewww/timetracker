import Foundation

extension TimeTrackerStore {
    @discardableResult
    func moveInboxItem(_ item: InboxItem, toTaskID taskID: UUID) -> Bool {
        moveInboxItem(
            baseline: InboxMoveToTaskBaseline(item: item),
            toTaskID: taskID
        )
    }

    @discardableResult
    func moveInboxItem(
        baseline: InboxMoveToTaskBaseline,
        toTaskID taskID: UUID
    ) -> Bool {
        let outcome = performStoreScopedInboxMutation(
            refreshScopes: [.inbox, .tasks, .checklist],
            eventsForOutcome: { (outcome: InboxChecklistRouteOutcome) in
                outcome.events
            }
        ) { coordinator in
            try coordinator.moveToTask(
                baseline: baseline,
                taskID: taskID
            )
        }
        if outcome?.didMutate == true {
            inboxSuggestionFailureByItemID[baseline.itemID] = nil
            return true
        }
        return false
    }
}
