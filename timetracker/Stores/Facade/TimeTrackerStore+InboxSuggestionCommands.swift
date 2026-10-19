import Foundation

extension TimeTrackerStore {
    func applyInboxSuggestion(baseline: InboxSuggestionApplyBaseline) throws {
        let outcome: InboxManualRouteOutcome
        do {
            outcome = try performStoreScopedInboxMutation(
                refreshScopes: [.inbox, .tasks, .checklist],
                eventsForOutcome: { (outcome: InboxManualRouteOutcome) in outcome.events }
            ) { coordinator in
                try coordinator.applySuggestion(baseline: baseline)
            }
        } catch {
            inboxSuggestionFailureByItemID[baseline.itemID] = error.localizedDescription
            throw error
        }
        if outcome.didMutate {
            inboxSuggestionFailureByItemID[baseline.itemID] = nil
        }
    }
}
