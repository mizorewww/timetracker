import Foundation

extension TimeTrackerStore {
    func applyInboxSuggestion(baseline: InboxSuggestionApplyBaseline) {
        let outcome = performStoreScopedInboxMutation(
            refreshScopes: [.inbox, .tasks, .checklist],
            eventsForOutcome: { (outcome: InboxManualRouteOutcome) in outcome.events }
        ) { coordinator in
            try coordinator.applySuggestion(baseline: baseline)
        }
        if outcome?.didMutate == true {
            inboxSuggestionFailureByItemID[baseline.itemID] = nil
        } else if outcome == nil {
            inboxSuggestionFailureByItemID[baseline.itemID] = errorMessage
        }
    }
}
