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

    func applyInboxSuggestion(_ item: InboxItem) {
        guard let suggestion = inboxSuggestion(for: item),
              trackableTaskIDs.contains(suggestion.taskID) else {
            fail(.invalidInboxSuggestion)
            return
        }
        let outcome = performStoreScopedInboxMutation(
            refreshScopes: [.inbox, .tasks, .checklist],
            eventsForOutcome: { (outcome: InboxSuggestionApplyOutcome) in outcome.events }
        ) { coordinator in
            try coordinator.applySuggestion(
                baseline: InboxSuggestionApplyBaseline(
                    item: item,
                    suggestion: suggestion
                )
            )
        }
        if outcome?.didMutate == true {
            inboxSuggestionFailureByItemID[item.id] = nil
        } else if outcome == nil {
            inboxSuggestionFailureByItemID[item.id] = errorMessage
        }
    }
}
