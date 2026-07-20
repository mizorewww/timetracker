import Foundation

extension TimeTrackerStore {
    @discardableResult
    func saveInboxSuggestionDraft(_ draft: InboxSuggestionEditorDraft) -> Bool {
        guard let item = inboxItems.first(where: { $0.id == draft.inboxItemID }) else { return false }
        guard draft.taskID != nil else {
            return fail(.invalidInboxSuggestion)
        }
        let outcome = performStoreScopedInboxMutation(
            refreshScopes: [.inbox, .tasks],
            eventsForOutcome: { (outcome: InboxMutationOutcome) in outcome.events }
        ) { coordinator in
            try coordinator.saveSuggestionDraft(
                baseline: InboxItemMutationBaseline(item: item),
                draft: draft
            )
        }
        return outcome?.didMutate == true
    }

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
