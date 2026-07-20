import Foundation

extension TimeTrackerStore {
    @discardableResult
    func routeInboxItemAsChildTask(
        baseline: InboxManualRouteBaseline,
        parentTaskID: UUID
    ) -> Bool {
        routeInboxItem(
            baseline: baseline,
            destination: .childTask(parentTaskID: parentTaskID)
        )
    }

    @discardableResult
    func routeInboxItemToCategory(
        baseline: InboxManualRouteBaseline,
        categoryID: UUID
    ) -> Bool {
        routeInboxItem(
            baseline: baseline,
            destination: .category(categoryID: categoryID)
        )
    }

    @discardableResult
    func routeInboxItemAsChecklist(
        baseline: InboxManualRouteBaseline,
        taskID: UUID
    ) -> Bool {
        routeInboxItem(
            baseline: baseline,
            destination: .checklist(taskID: taskID)
        )
    }

    private func routeInboxItem(
        baseline: InboxManualRouteBaseline,
        destination: InboxManualRouteDestination
    ) -> Bool {
        let outcome = performStoreScopedInboxMutation(
            refreshScopes: [.inbox, .tasks, .checklist],
            eventsForOutcome: { (outcome: InboxManualRouteOutcome) in
                outcome.events
            }
        ) { coordinator in
            try coordinator.route(
                baseline: baseline,
                destination: destination
            )
        }
        if outcome?.didMutate == true {
            inboxSuggestionFailureByItemID[baseline.itemID] = nil
            return true
        }
        return false
    }
}
