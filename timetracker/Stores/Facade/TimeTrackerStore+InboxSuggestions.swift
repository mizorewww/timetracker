import Foundation

extension TimeTrackerStore {
    private static let maximumInboxSuggestionConcurrency = 3

    func autoSuggestInboxItemsIfNeeded() {
        guard canAutoSuggestInboxItems else { return }
        let candidates = llmInboxSuggestionCandidates()
        guard !candidates.isEmpty else { return }
        let availableSlots = max(
            0,
            Self.maximumInboxSuggestionConcurrency - inboxSuggestionInFlightIDs.count
        )
        guard availableSlots > 0 else { return }

        for item in openInboxItems
            where shouldAutoSuggestInboxItem(item) && inboxSuggestionFailureByItemID[item.id] == nil
        {
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
              item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
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
        guard !inboxSuggestionInFlightIDs.contains(item.id),
              inboxSuggestionInFlightIDs.count < Self.maximumInboxSuggestionConcurrency
        else {
            enqueueInboxSuggestion(itemID: item.id, showsErrors: showsErrors)
            return
        }
        let endpoint = preferences.llmEndpoint
        let apiKey = preferences.llmAPIKey
        let modelID = preferences.llmSelectedModel
        let instructions = preferences.llmInboxSuggestionInstructions
        let itemID = item.id
        let requestedTitle = item.title
        let requestedIdentity = item.suggestionIdentity
        let requestID = UUID()
        let service = inboxSuggestionService
        inboxSuggestionFailureByItemID[item.id] = nil
        inboxSuggestionInFlightIDs.insert(item.id)

        let task = Task { @MainActor [weak self] in
            do {
                let result = try await service.suggest(
                    inboxTitle: requestedTitle,
                    taskCandidates: candidates.tasks,
                    categoryCandidates: candidates.categories,
                    instructions: instructions,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    modelID: modelID
                )
                try Task.checkCancellation()
                self?.completeInboxSuggestion(
                    result,
                    itemID: itemID,
                    requestID: requestID,
                    requestedTitle: requestedTitle,
                    requestedIdentity: requestedIdentity,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    modelID: modelID,
                    instructions: instructions,
                    showsErrors: showsErrors
                )
            } catch {
                self?.completeInboxSuggestionFailure(
                    error,
                    itemID: itemID,
                    requestID: requestID,
                    requestedTitle: requestedTitle,
                    requestedIdentity: requestedIdentity,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    modelID: modelID,
                    instructions: instructions,
                    showsErrors: showsErrors,
                    wasCancelled: Task.isCancelled || error is CancellationError
                )
            }
        }
        inboxSuggestionTasksByItemID[itemID] = StoreLLMSuggestionTask(
            requestID: requestID,
            isAutomatic: !showsErrors,
            task: task
        )
    }

    func startPendingInboxSuggestionsIfNeeded() {
        while inboxSuggestionInFlightIDs.count < Self.maximumInboxSuggestionConcurrency,
              inboxSuggestionPendingIDs.isEmpty == false
        {
            let itemID = inboxSuggestionPendingIDs.removeFirst()
            let showsErrors = inboxSuggestionPendingShowsErrors.remove(itemID) != nil
            guard let item = inboxItems.first(where: { $0.id == itemID }) else { continue }
            requestInboxSuggestion(item, showsErrors: showsErrors)
        }
    }

    func cancelAllInboxSuggestionRequests() {
        inboxSuggestionPendingIDs.removeAll(keepingCapacity: true)
        inboxSuggestionPendingShowsErrors.removeAll(keepingCapacity: true)
        cancelInboxSuggestionRequests { _ in true }
    }

    func cancelInboxSuggestionRequests(matching requestIDsByItemID: [UUID: UUID]) {
        guard !requestIDsByItemID.isEmpty else { return }
        inboxSuggestionPendingIDs.removeAll(keepingCapacity: true)
        inboxSuggestionPendingShowsErrors.removeAll(keepingCapacity: true)
        cancelInboxSuggestionRequests { itemID, request in
            requestIDsByItemID[itemID] == request.requestID
        }
    }

    func cancelAutomaticInboxSuggestionRequests() {
        inboxSuggestionPendingIDs.removeAll { itemID in
            inboxSuggestionPendingShowsErrors.contains(itemID) == false
        }
        cancelInboxSuggestionRequests { $0.value.isAutomatic }
        startPendingInboxSuggestionsIfNeeded()
    }

    func cancelInboxSuggestionRequests(for itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty else { return }
        inboxSuggestionPendingIDs.removeAll { itemIDs.contains($0) }
        inboxSuggestionPendingShowsErrors.subtract(itemIDs)
        cancelInboxSuggestionRequests { itemIDs.contains($0.key) }
    }

    func cancelInvalidInboxSuggestionRequests() {
        let validItemIDs = Set(
            inboxItems.lazy
                .filter { $0.deletedAt == nil && $0.isCompleted == false }
                .map(\.id)
        )
        cancelInboxSuggestionRequests(for: inboxSuggestionInFlightIDs.subtracting(validItemIDs))
    }

    private func cancelInboxSuggestionRequests(
        shouldCancel: (Dictionary<UUID, StoreLLMSuggestionTask>.Element) -> Bool
    ) {
        let requests = inboxSuggestionTasksByItemID.filter(shouldCancel)
        for (itemID, request) in requests {
            guard inboxSuggestionTasksByItemID[itemID]?.requestID == request.requestID else { continue }
            inboxSuggestionTasksByItemID.removeValue(forKey: itemID)
            inboxSuggestionInFlightIDs.remove(itemID)
            request.task.cancel()
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
            readModel: inboxItemReadModel(for: item),
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

    func matchesCurrentLLMPrompt(
        _ instructions: String,
        kind: LLMPromptKind
    ) -> Bool {
        preferences.llmInstructions(for: kind) == instructions
    }
}
