import Foundation

extension TimeTrackerStore {
    func presentInboxSuggestionEditor(_ item: InboxItem) {
        inboxSuggestionEditorDraft = InboxSuggestionEditorDraft(
            item: item,
            suggestion: inboxSuggestion(for: item),
            fallbackTaskID: tasks.first?.id
        )
    }

    @discardableResult
    func saveInboxSuggestionDraft(_ draft: InboxSuggestionEditorDraft) -> Bool {
        guard let item = inboxItems.first(where: { $0.id == draft.inboxItemID }) else { return false }
        let didSave = perform(event: .inboxChanged(itemIDs: [item.id])) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.saveSuggestionDraft(
                item: item,
                draft: draft,
                context: modelContext
            )
        }
        if didSave {
            inboxSuggestionEditorDraft = nil
        }
        return didSave
    }

    func applyInboxSuggestion(_ item: InboxItem) {
        guard let suggestion = inboxSuggestion(for: item),
              taskByID[suggestion.taskID] != nil else {
            fail(.invalidInboxSuggestion)
            return
        }
        perform(events: [
            .inboxChanged(itemIDs: [item.id]),
            .checklistChanged(taskID: suggestion.taskID, affectedAncestorIDs: affectedAncestorIDs(for: suggestion.taskID))
        ]) {
            guard let modelContext else { throw StoreError.notConfigured }
            _ = try inboxCommandHandler.applySuggestion(
                item: item,
                suggestion: suggestion,
                existingChecklistItems: checklistItems(for: suggestion.taskID),
                context: modelContext
            )
        }
        inboxSuggestionFailureByItemID[item.id] = nil
    }
}
