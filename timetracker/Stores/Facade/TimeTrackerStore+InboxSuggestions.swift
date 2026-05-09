import Foundation

extension TimeTrackerStore {
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
        inboxSuggestionFailureByItemID[item.id] = nil
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
                    guard inboxSuggestionStateService.canStoreGeneratedSuggestion(
                        item: item,
                        requestedTitle: requestedTitle,
                        currentSuggestion: inboxSuggestionByItemID[item.id]
                    ) else {
                        inboxSuggestionInFlightIDs.remove(item.id)
                        return
                    }
                    _ = perform(event: .inboxChanged(itemIDs: [item.id])) {
                        guard let modelContext else { throw StoreError.notConfigured }
                        try inboxCommandHandler.upsertSuggestion(
                            item: item,
                            result: result,
                            context: modelContext
                        )
                    }
                    inboxSuggestionFailureByItemID[item.id] = nil
                    inboxSuggestionInFlightIDs.remove(item.id)
                }
            } catch {
                await MainActor.run {
                    inboxSuggestionFailureByItemID[item.id] = error.localizedDescription
                    if showsErrors {
                        errorMessage = error.localizedDescription
                    }
                    inboxSuggestionInFlightIDs.remove(item.id)
                }
            }
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
        inboxSuggestionStateService.shouldAutoSuggest(
            item: item,
            suggestion: inboxSuggestionByItemID[item.id],
            isInFlight: inboxSuggestionInFlightIDs.contains(item.id)
        )
    }

    func retryInboxSuggestion(_ item: InboxItem) {
        inboxSuggestionFailureByItemID[item.id] = nil
        suggestInboxItem(item, showsErrors: true)
    }
}
