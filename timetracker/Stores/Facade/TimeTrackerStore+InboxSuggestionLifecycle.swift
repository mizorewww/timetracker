import Foundation

extension TimeTrackerStore {
    func completeInboxSuggestion(
        _ result: LLMInboxSuggestionResult,
        itemID: UUID,
        requestID: UUID,
        requestedTitle: String,
        requestedIdentity: InboxSuggestionIdentity,
        endpoint: String,
        apiKey: String,
        modelID: String,
        instructions: String,
        showsErrors: Bool
    ) {
        guard isCurrentInboxSuggestionRequest(itemID: itemID, requestID: requestID) else { return }
        defer { finishInboxSuggestionRequest(itemID: itemID, requestID: requestID) }

        guard matchesCurrentLLMConfiguration(
            endpoint: endpoint,
            apiKey: apiKey,
            modelID: modelID
        ), matchesCurrentLLMPrompt(instructions, kind: .inboxRouting),
        showsErrors || preferences.llmAutomaticSuggestionsEnabled else {
            return
        }

        let outcome = performStoreScopedInboxMutation(
            refreshScopes: [.inbox, .tasks],
            eventsForOutcome: { (outcome: InboxMutationOutcome) in outcome.events }
        ) { coordinator in
            try coordinator.storeGeneratedSuggestion(
                itemID: itemID,
                requestedTitle: requestedTitle,
                requestedIdentity: requestedIdentity,
                result: result
            )
        }
        if outcome?.didMutate == true {
            inboxSuggestionFailureByItemID[itemID] = nil
        } else if outcome == nil {
            inboxSuggestionFailureByItemID[itemID] = errorMessage
        } else {
            refreshStoreScopedInboxReadModels(scopes: [.inbox, .tasks])
        }
    }

    func completeInboxSuggestionFailure(
        _ error: Error,
        itemID: UUID,
        requestID: UUID,
        requestedTitle: String,
        requestedIdentity: InboxSuggestionIdentity,
        endpoint: String,
        apiKey: String,
        modelID: String,
        instructions: String,
        showsErrors: Bool,
        wasCancelled: Bool
    ) {
        guard isCurrentInboxSuggestionRequest(itemID: itemID, requestID: requestID) else { return }
        if wasCancelled {
            removePendingInboxSuggestion(itemID: itemID)
            finishInboxSuggestionRequest(
                itemID: itemID,
                requestID: requestID,
                shouldAutoSuggest: false
            )
            return
        }
        defer { finishInboxSuggestionRequest(itemID: itemID, requestID: requestID) }

        guard matchesCurrentLLMConfiguration(
            endpoint: endpoint,
            apiKey: apiKey,
            modelID: modelID
        ), matchesCurrentLLMPrompt(instructions, kind: .inboxRouting),
        showsErrors || preferences.llmAutomaticSuggestionsEnabled,
        let item = inboxItems.first(where: { $0.id == itemID }),
        inboxSuggestionStateService.canStoreGeneratedSuggestion(
            readModel: inboxItemReadModel(for: item),
            requestedTitle: requestedTitle,
            requestedIdentity: requestedIdentity,
            currentSuggestion: inboxSuggestionByItemID[itemID]
        ) else {
            return
        }
        inboxSuggestionFailureByItemID[itemID] = error.localizedDescription
        if showsErrors {
            errorMessage = error.localizedDescription
        }
    }

    func enqueueInboxSuggestion(itemID: UUID, showsErrors: Bool) {
        if inboxSuggestionPendingIDs.contains(itemID) == false {
            inboxSuggestionPendingIDs.append(itemID)
        }
        if showsErrors {
            inboxSuggestionPendingShowsErrors.insert(itemID)
        }
    }

    private func finishInboxSuggestionRequest(
        itemID: UUID,
        requestID: UUID,
        shouldAutoSuggest: Bool = true
    ) {
        guard isCurrentInboxSuggestionRequest(itemID: itemID, requestID: requestID) else { return }
        inboxSuggestionTasksByItemID.removeValue(forKey: itemID)
        inboxSuggestionInFlightIDs.remove(itemID)
        startPendingInboxSuggestionsIfNeeded()
        if shouldAutoSuggest {
            autoSuggestInboxItemsIfNeeded()
        }
    }

    private func removePendingInboxSuggestion(itemID: UUID) {
        inboxSuggestionPendingIDs.removeAll { $0 == itemID }
        inboxSuggestionPendingShowsErrors.remove(itemID)
    }

    private func isCurrentInboxSuggestionRequest(itemID: UUID, requestID: UUID) -> Bool {
        inboxSuggestionTasksByItemID[itemID]?.requestID == requestID
    }
}
