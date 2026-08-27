import Foundation

extension TimeTrackerStore {
    func autoSuggestInboxItemsIfNeeded() {
        guard canAutoSuggestLLMSuggestions else { return }
        let candidates = llmInboxSuggestionCandidates()
        guard !candidates.isEmpty else { return }
        guard inboxSuggestionLifecycle.availableSlots > 0 else { return }

        for item in openInboxItems
            where shouldAutoSuggestInboxItem(item) &&
            inboxSuggestionLifecycle.failureByItemID[item.id] == nil
        {
            guard inboxSuggestionLifecycle.availableSlots > 0 else { break }
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
              item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return
        }

        guard !inboxSuggestionLifecycle.inFlightIDs.contains(item.id),
              inboxSuggestionLifecycle.availableSlots > 0
        else {
            inboxSuggestionLifecycle.enqueue(itemID: item.id, showsErrors: showsErrors)
            return
        }

        startInboxSuggestion(
            item,
            candidates: llmInboxSuggestionCandidates(),
            showsErrors: showsErrors
        )
    }

    private func startInboxSuggestion(
        _ item: InboxItem,
        candidates: LLMInboxSuggestionCandidates,
        showsErrors: Bool
    ) {
        guard !inboxSuggestionLifecycle.inFlightIDs.contains(item.id),
              inboxSuggestionLifecycle.availableSlots > 0
        else {
            inboxSuggestionLifecycle.enqueue(itemID: item.id, showsErrors: showsErrors)
            return
        }
        let request = InboxSuggestionRequest(
            itemID: item.id,
            requestedTitle: item.title,
            requestedIdentity: item.suggestionIdentity,
            instructions: preferences.llmInboxSuggestionInstructions,
            configuration: preferences.llmRequestConfiguration,
            showsErrors: showsErrors
        )
        let service = inboxSuggestionService
        inboxSuggestionLifecycle.failureByItemID[item.id] = nil

        inboxSuggestionLifecycle.start(
            itemID: item.id,
            isAutomatic: !showsErrors,
            perform: {
                try await service.suggest(
                    inboxTitle: request.requestedTitle,
                    taskCandidates: candidates.tasks,
                    categoryCandidates: candidates.categories,
                    instructions: request.instructions,
                    configuration: request.configuration
                )
            },
            onSuccess: { [weak self] result, requestID in
                self?.completeInboxSuggestion(
                    result,
                    request: request,
                    requestID: requestID
                )
            },
            onFailure: { [weak self] error, requestID, wasCancelled in
                self?.completeInboxSuggestionFailure(
                    error,
                    request: request,
                    requestID: requestID,
                    wasCancelled: wasCancelled
                )
            }
        )
    }

    func startPendingInboxSuggestionsIfNeeded() {
        while inboxSuggestionLifecycle.availableSlots > 0,
              let pending = inboxSuggestionLifecycle.dequeuePending()
        {
            guard let item = inboxItems.first(where: { $0.id == pending.itemID }) else { continue }
            requestInboxSuggestion(item, showsErrors: pending.showsErrors)
        }
    }

    func cancelAllInboxSuggestionRequests() {
        inboxSuggestionLifecycle.clearPending()
        inboxSuggestionLifecycle.cancelInFlight { _, _ in true }
    }

    func cancelInboxSuggestionRequests(matching requestIDsByItemID: [UUID: UUID]) {
        guard !requestIDsByItemID.isEmpty else { return }
        inboxSuggestionLifecycle.clearPending()
        inboxSuggestionLifecycle.cancelInFlight(matching: requestIDsByItemID)
    }

    func cancelAutomaticInboxSuggestionRequests() {
        inboxSuggestionLifecycle.removeAutomaticPending()
        inboxSuggestionLifecycle.cancelInFlight { _, request in request.isAutomatic }
        startPendingInboxSuggestionsIfNeeded()
    }

    func cancelInboxSuggestionRequests(for itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty else { return }
        inboxSuggestionLifecycle.removePending(for: itemIDs)
        inboxSuggestionLifecycle.cancelInFlight(for: itemIDs)
    }

    func cancelInvalidInboxSuggestionRequests() {
        let validItemIDs = Set(
            inboxItems.lazy
                .filter { $0.deletedAt == nil && $0.isCompleted == false }
                .map(\.id)
        )
        cancelInboxSuggestionRequests(
            for: inboxSuggestionLifecycle.inFlightIDs.subtracting(validItemIDs)
        )
    }

    var canAutoSuggestLLMSuggestions: Bool {
        preferences.llmAutomaticSuggestionsEnabled &&
            preferences.llmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            preferences.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            preferences.llmSelectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func shouldAutoSuggestInboxItem(_ item: InboxItem) -> Bool {
        inboxSuggestionStateService.shouldAutoSuggest(
            readModel: inboxItemReadModel(for: item),
            suggestion: inboxSuggestionByItemID[item.id],
            isInFlight: inboxSuggestionLifecycle.inFlightIDs.contains(item.id)
        )
    }

    func retryInboxSuggestion(_ item: InboxItem) {
        inboxSuggestionLifecycle.failureByItemID[item.id] = nil
        suggestInboxItem(item, showsErrors: true)
    }

    func matchesCurrentLLMConfiguration(_ configuration: LLMRequestConfiguration) -> Bool {
        preferences.llmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines) ==
            configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines) &&
            preferences.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines) ==
            configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines) &&
            preferences.llmSelectedModel.trimmingCharacters(in: .whitespacesAndNewlines) ==
            configuration.modelID.trimmingCharacters(in: .whitespacesAndNewlines) &&
            preferences.llmReasoningEffort == configuration.reasoningEffort
    }

    func matchesCurrentLLMPrompt(
        _ instructions: String,
        kind: LLMPromptKind
    ) -> Bool {
        preferences.llmInstructions(for: kind) == instructions
    }
}
