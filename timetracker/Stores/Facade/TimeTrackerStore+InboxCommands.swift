import Foundation

extension TimeTrackerStore {
    var openInboxItems: [InboxItem] {
        inboxItems
            .filter { !$0.isCompleted && $0.deletedAt == nil }
            .sorted(by: inboxSort)
    }

    var completedInboxItems: [InboxItem] {
        inboxItems
            .filter { $0.isCompleted && $0.deletedAt == nil }
            .sorted(by: inboxSort)
    }

    var inboxItemsForDisplay: [InboxItem] {
        openInboxItems + completedInboxItems
    }

    func addInboxItem(title: String) {
        perform(event: .inboxChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.add(
                title: title,
                existingItems: inboxItems,
                context: modelContext
            )
        }
    }

    func toggleInboxItem(_ item: InboxItem) {
        perform(event: .inboxChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.toggle(item, context: modelContext)
        }
    }

    func updateInboxItemTitle(_ item: InboxItem, title: String) {
        perform(event: .inboxChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.updateTitle(item, title: title, context: modelContext)
        }
    }

    func deleteInboxItem(_ item: InboxItem) {
        perform(event: .inboxChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.softDelete(item, context: modelContext)
        }
    }

    func suggestInboxItem(_ item: InboxItem) {
        guard !inboxSuggestionInFlightIDs.contains(item.id) else { return }
        let endpoint = preferences.llmEndpoint
        let apiKey = preferences.llmAPIKey
        let modelID = preferences.llmSelectedModel
        let candidates = llmTaskCandidates()
        inboxSuggestionInFlightIDs.insert(item.id)

        Task {
            do {
                let result = try await LLMInboxSuggestionService().suggest(
                    inboxTitle: item.title,
                    candidates: candidates,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    modelID: modelID
                )
                await MainActor.run {
                    _ = perform(event: .inboxChanged) {
                        guard let modelContext else { throw StoreError.notConfigured }
                        try inboxCommandHandler.upsertSuggestion(
                            item: item,
                            result: result,
                            context: modelContext
                        )
                    }
                    inboxSuggestionInFlightIDs.remove(item.id)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    inboxSuggestionInFlightIDs.remove(item.id)
                }
            }
        }
    }

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
        let didSave = perform(event: .inboxChanged) {
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
            errorMessage = AppStrings.localized("inbox.suggestion.error.noValidTask")
            return
        }
        perform(events: [
            .inboxChanged,
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
    }

    private func llmTaskCandidates() -> [LLMTaskCandidate] {
        tasks
            .filter { $0.deletedAt == nil && $0.archivedAt == nil }
            .sorted { lhs, rhs in
                if lhs.path == rhs.path {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.path < rhs.path
            }
            .map { task in
                LLMTaskCandidate(
                    id: task.id,
                    title: task.title,
                    path: taskPath(for: task),
                    iconName: ChecklistVisualSanitizer.sanitizedIcon(task.iconName),
                    colorHex: ChecklistVisualSanitizer.sanitizedColor(task.colorHex)
                )
            }
    }

    private func inboxSort(_ lhs: InboxItem, _ rhs: InboxItem) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.createdAt < rhs.createdAt
    }
}
