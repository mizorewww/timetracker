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
        let oldTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let didUpdate = perform(event: .inboxChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.updateTitle(item, title: title, context: modelContext)
        }
        if didUpdate, !newTitle.isEmpty, newTitle != oldTitle {
            suggestInboxItem(item, showsErrors: false)
        }
    }

    func deleteInboxItem(_ item: InboxItem) {
        perform(event: .inboxChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.softDelete(item, context: modelContext)
        }
    }

    func discardInboxSuggestion(_ item: InboxItem) {
        perform(event: .inboxChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.discardSuggestion(item, context: modelContext)
        }
    }

    func autoSuggestInboxItemsIfNeeded() {
        guard canAutoSuggestInboxItems else { return }
        let candidates = llmTaskCandidates()
        guard !candidates.isEmpty else { return }

        for item in openInboxItems where shouldAutoSuggestInboxItem(item) {
            suggestInboxItem(item, candidates: candidates, showsErrors: false)
        }
    }

    func suggestInboxItem(_ item: InboxItem, showsErrors: Bool = true) {
        suggestInboxItem(item, candidates: llmTaskCandidates(), showsErrors: showsErrors)
    }

    private func suggestInboxItem(_ item: InboxItem, candidates: [LLMTaskCandidate], showsErrors: Bool) {
        guard !inboxSuggestionInFlightIDs.contains(item.id) else { return }
        guard item.deletedAt == nil,
              item.isCompleted == false,
              item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }
        let endpoint = preferences.llmEndpoint
        let apiKey = preferences.llmAPIKey
        let modelID = preferences.llmSelectedModel
        let requestedTitle = item.title
        inboxSuggestionInFlightIDs.insert(item.id)

        Task {
            do {
                let result = try await LLMInboxSuggestionService().suggest(
                    inboxTitle: requestedTitle,
                    candidates: candidates,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    modelID: modelID
                )
                await MainActor.run {
                    guard item.deletedAt == nil, item.title == requestedTitle else {
                        inboxSuggestionInFlightIDs.remove(item.id)
                        return
                    }
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
                    if showsErrors {
                        errorMessage = error.localizedDescription
                    }
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

    private var canAutoSuggestInboxItems: Bool {
        preferences.llmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            preferences.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            preferences.llmSelectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func shouldAutoSuggestInboxItem(_ item: InboxItem) -> Bool {
        item.deletedAt == nil &&
            item.isCompleted == false &&
            item.suggestionGeneratedAt == nil &&
            inboxSuggestion(for: item) == nil &&
            !inboxSuggestionInFlightIDs.contains(item.id) &&
            !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func inboxSort(_ lhs: InboxItem, _ rhs: InboxItem) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        return lhs.createdAt < rhs.createdAt
    }
}
