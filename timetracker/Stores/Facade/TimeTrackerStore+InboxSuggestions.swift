import Foundation

extension TimeTrackerStore {
    private static let maximumInboxSuggestionConcurrency = 3

    func autoSuggestInboxItemsIfNeeded() {
        guard canAutoSuggestInboxItems else { return }
        let candidates = llmTaskCandidates()
        guard !candidates.isEmpty else { return }
        let availableSlots = max(
            0,
            Self.maximumInboxSuggestionConcurrency - inboxSuggestionInFlightIDs.count
        )
        guard availableSlots > 0 else { return }

        for item in openInboxItems
        where shouldAutoSuggestInboxItem(item) && inboxSuggestionFailureByItemID[item.id] == nil {
            guard inboxSuggestionInFlightIDs.count < Self.maximumInboxSuggestionConcurrency else { break }
            startInboxSuggestion(item, candidates: candidates, showsErrors: false)
        }
    }

    func suggestInboxItem(_ item: InboxItem, showsErrors: Bool = true) {
        guard showsErrors || preferences.llmAutomaticSuggestionsEnabled else { return }
        requestInboxSuggestion(item, showsErrors: showsErrors)
    }

    private func requestInboxSuggestion(_ item: InboxItem, showsErrors: Bool) {
        guard item.deletedAt == nil,
              item.isCompleted == false,
              item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return
        }

        guard !inboxSuggestionInFlightIDs.contains(item.id) else {
            enqueueInboxSuggestion(itemID: item.id, showsErrors: showsErrors)
            return
        }

        guard inboxSuggestionInFlightIDs.count < Self.maximumInboxSuggestionConcurrency else {
            enqueueInboxSuggestion(itemID: item.id, showsErrors: showsErrors)
            return
        }

        startInboxSuggestion(item, candidates: llmTaskCandidates(), showsErrors: showsErrors)
    }

    private func startInboxSuggestion(
        _ item: InboxItem,
        candidates: [LLMTaskCandidate],
        showsErrors: Bool
    ) {
        guard !inboxSuggestionInFlightIDs.contains(item.id),
              inboxSuggestionInFlightIDs.count < Self.maximumInboxSuggestionConcurrency else {
            enqueueInboxSuggestion(itemID: item.id, showsErrors: showsErrors)
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
                let result = try await inboxSuggestionService.suggest(
                    inboxTitle: requestedTitle,
                    candidates: candidates,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    modelID: modelID
                )
                await MainActor.run {
                    guard matchesCurrentLLMConfiguration(
                        endpoint: endpoint,
                        apiKey: apiKey,
                        modelID: modelID
                    ) else {
                        finishInboxSuggestionRequest(itemID: item.id)
                        return
                    }
                    guard showsErrors || preferences.llmAutomaticSuggestionsEnabled else {
                        finishInboxSuggestionRequest(itemID: item.id)
                        return
                    }
                    guard inboxSuggestionStateService.canStoreGeneratedSuggestion(
                        item: item,
                        requestedTitle: requestedTitle,
                        currentSuggestion: inboxSuggestionByItemID[item.id]
                    ) else {
                        finishInboxSuggestionRequest(itemID: item.id)
                        return
                    }
                    guard trackableTaskIDs.contains(result.taskID) else {
                        finishInboxSuggestionRequest(itemID: item.id)
                        return
                    }
                    let didSave = perform(event: .inboxChanged(itemIDs: [item.id])) {
                        guard let modelContext else { throw StoreError.notConfigured }
                        try inboxCommandHandler.upsertSuggestion(
                            item: item,
                            result: result,
                            context: modelContext
                        )
                    }
                    inboxSuggestionFailureByItemID[item.id] = didSave ? nil : errorMessage
                    finishInboxSuggestionRequest(itemID: item.id)
                }
            } catch {
                await MainActor.run {
                    guard matchesCurrentLLMConfiguration(
                        endpoint: endpoint,
                        apiKey: apiKey,
                        modelID: modelID
                    ), showsErrors || preferences.llmAutomaticSuggestionsEnabled else {
                        finishInboxSuggestionRequest(itemID: item.id)
                        return
                    }
                    inboxSuggestionFailureByItemID[item.id] = error.localizedDescription
                    if showsErrors {
                        errorMessage = error.localizedDescription
                    }
                    finishInboxSuggestionRequest(itemID: item.id)
                }
            }
        }
    }

    private func enqueueInboxSuggestion(itemID: UUID, showsErrors: Bool) {
        if inboxSuggestionPendingIDs.contains(itemID) == false {
            inboxSuggestionPendingIDs.append(itemID)
        }
        if showsErrors {
            inboxSuggestionPendingShowsErrors.insert(itemID)
        }
    }

    private func finishInboxSuggestionRequest(itemID: UUID) {
        inboxSuggestionInFlightIDs.remove(itemID)
        startPendingInboxSuggestionsIfNeeded()
        autoSuggestInboxItemsIfNeeded()
    }

    private func startPendingInboxSuggestionsIfNeeded() {
        while inboxSuggestionInFlightIDs.count < Self.maximumInboxSuggestionConcurrency,
              inboxSuggestionPendingIDs.isEmpty == false {
            let itemID = inboxSuggestionPendingIDs.removeFirst()
            let showsErrors = inboxSuggestionPendingShowsErrors.remove(itemID) != nil
            guard let item = inboxItems.first(where: { $0.id == itemID }) else { continue }
            requestInboxSuggestion(item, showsErrors: showsErrors)
        }
    }

    private func llmTaskCandidates() -> [LLMTaskCandidate] {
        tasks
            .filter(isTaskAvailableForTracking)
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
        preferences.llmAutomaticSuggestionsEnabled &&
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

    func matchesCurrentLLMConfiguration(
        endpoint: String,
        apiKey: String,
        modelID: String
    ) -> Bool {
        preferences.llmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines) ==
            endpoint.trimmingCharacters(in: .whitespacesAndNewlines) &&
            preferences.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines) ==
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines) &&
            preferences.llmSelectedModel.trimmingCharacters(in: .whitespacesAndNewlines) ==
            modelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
