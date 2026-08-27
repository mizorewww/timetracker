import Foundation

extension TimeTrackerStore {
    func completeInboxSuggestion(
        _ result: LLMInboxSuggestionResult,
        request: InboxSuggestionRequest,
        requestID: UUID
    ) {
        guard inboxSuggestionLifecycle.isCurrentRequest(
            itemID: request.itemID,
            requestID: requestID
        ) else { return }
        defer {
            finishInboxSuggestionRequest(
                itemID: request.itemID,
                requestID: requestID
            )
        }

        guard matchesCurrentLLMConfiguration(request.configuration),
              matchesCurrentLLMPrompt(request.instructions, kind: .inboxRouting),
              request.showsErrors || preferences.llmAutomaticSuggestionsEnabled
        else {
            return
        }

        let outcome = performStoreScopedInboxMutation(
            refreshScopes: [.inbox, .tasks],
            eventsForOutcome: { (outcome: InboxMutationOutcome) in outcome.events }
        ) { coordinator in
            try coordinator.storeGeneratedSuggestion(
                itemID: request.itemID,
                requestedTitle: request.requestedTitle,
                requestedIdentity: request.requestedIdentity,
                result: result
            )
        }
        if outcome?.didMutate == true {
            inboxSuggestionLifecycle.failureByItemID[request.itemID] = nil
        } else if outcome == nil {
            inboxSuggestionLifecycle.failureByItemID[request.itemID] = errorMessage
        } else {
            refreshStoreScopedInboxReadModels(scopes: [.inbox, .tasks])
        }
    }

    func completeInboxSuggestionFailure(
        _ error: Error,
        request: InboxSuggestionRequest,
        requestID: UUID,
        wasCancelled: Bool
    ) {
        guard inboxSuggestionLifecycle.isCurrentRequest(
            itemID: request.itemID,
            requestID: requestID
        ) else { return }
        if wasCancelled {
            inboxSuggestionLifecycle.removePending(itemID: request.itemID)
            finishInboxSuggestionRequest(
                itemID: request.itemID,
                requestID: requestID,
                shouldAutoSuggest: false
            )
            return
        }
        defer {
            finishInboxSuggestionRequest(
                itemID: request.itemID,
                requestID: requestID
            )
        }

        guard matchesCurrentLLMConfiguration(request.configuration),
              matchesCurrentLLMPrompt(request.instructions, kind: .inboxRouting),
              request.showsErrors || preferences.llmAutomaticSuggestionsEnabled,
              let item = inboxItems.first(where: { $0.id == request.itemID }),
              inboxSuggestionStateService.canStoreGeneratedSuggestion(
                  readModel: inboxItemReadModel(for: item),
                  requestedTitle: request.requestedTitle,
                  requestedIdentity: request.requestedIdentity,
                  currentSuggestion: inboxSuggestionByItemID[request.itemID]
              )
        else {
            return
        }
        inboxSuggestionLifecycle.failureByItemID[request.itemID] = error.localizedDescription
        if request.showsErrors {
            errorMessage = error.localizedDescription
        }
    }

    private func finishInboxSuggestionRequest(
        itemID: UUID,
        requestID: UUID,
        shouldAutoSuggest: Bool = true
    ) {
        guard inboxSuggestionLifecycle.finish(itemID: itemID, requestID: requestID)
        else { return }
        startPendingInboxSuggestionsIfNeeded()
        if shouldAutoSuggest {
            autoSuggestInboxItemsIfNeeded()
        }
    }
}

struct InboxSuggestionRequest {
    let itemID: UUID
    let requestedTitle: String
    let requestedIdentity: InboxSuggestionIdentity
    let instructions: String
    let configuration: LLMRequestConfiguration
    let showsErrors: Bool
}
