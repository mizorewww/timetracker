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
        let itemID = item.id
        let requestedTitle = item.title
        let requestID = UUID()
        let service = inboxSuggestionService
        inboxSuggestionFailureByItemID[item.id] = nil
        inboxSuggestionInFlightIDs.insert(item.id)

        let task = Task { @MainActor [weak self] in
            do {
                let result = try await service.suggest(
                    inboxTitle: requestedTitle,
                    candidates: candidates,
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
                    endpoint: endpoint,
                    apiKey: apiKey,
                    modelID: modelID,
                    showsErrors: showsErrors
                )
            } catch {
                self?.completeInboxSuggestionFailure(
                    error,
                    itemID: itemID,
                    requestID: requestID,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    modelID: modelID,
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

    private func completeInboxSuggestion(
        _ result: LLMInboxSuggestionResult,
        itemID: UUID,
        requestID: UUID,
        requestedTitle: String,
        endpoint: String,
        apiKey: String,
        modelID: String,
        showsErrors: Bool
    ) {
        guard isCurrentInboxSuggestionRequest(itemID: itemID, requestID: requestID) else { return }
        defer { finishInboxSuggestionRequest(itemID: itemID, requestID: requestID) }

        guard matchesCurrentLLMConfiguration(
            endpoint: endpoint,
            apiKey: apiKey,
            modelID: modelID
        ), showsErrors || preferences.llmAutomaticSuggestionsEnabled,
              let item = inboxItems.first(where: { $0.id == itemID }),
              inboxSuggestionStateService.canStoreGeneratedSuggestion(
                  item: item,
                  requestedTitle: requestedTitle,
                  currentSuggestion: inboxSuggestionByItemID[itemID]
              ),
              trackableTaskIDs.contains(result.taskID) else {
            return
        }

        let didSave = perform(event: .inboxChanged(itemIDs: [itemID])) {
            guard let modelContext else { throw StoreError.notConfigured }
            try inboxCommandHandler.upsertSuggestion(
                item: item,
                result: result,
                context: modelContext
            )
        }
        inboxSuggestionFailureByItemID[itemID] = didSave ? nil : errorMessage
    }

    private func completeInboxSuggestionFailure(
        _ error: Error,
        itemID: UUID,
        requestID: UUID,
        endpoint: String,
        apiKey: String,
        modelID: String,
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
        ), showsErrors || preferences.llmAutomaticSuggestionsEnabled else {
            return
        }
        inboxSuggestionFailureByItemID[itemID] = error.localizedDescription
        if showsErrors {
            errorMessage = error.localizedDescription
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

    private func startPendingInboxSuggestionsIfNeeded() {
        while inboxSuggestionInFlightIDs.count < Self.maximumInboxSuggestionConcurrency,
              inboxSuggestionPendingIDs.isEmpty == false {
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

    private func removePendingInboxSuggestion(itemID: UUID) {
        inboxSuggestionPendingIDs.removeAll { $0 == itemID }
        inboxSuggestionPendingShowsErrors.remove(itemID)
    }

    private func isCurrentInboxSuggestionRequest(itemID: UUID, requestID: UUID) -> Bool {
        inboxSuggestionTasksByItemID[itemID]?.requestID == requestID
    }

    func llmTaskCandidates() -> [LLMTaskCandidate] {
        let availableTasks = tasks.filter(isTaskAvailableForTracking)
        var pinnedIDs = Set<UUID>()
        let pinnedTasks: [TaskNode] = preferences.quickStartTaskIDs.compactMap { taskID -> TaskNode? in
            guard pinnedIDs.insert(taskID).inserted,
                  let task = taskByID[taskID],
                  isTaskAvailableForTracking(task) else {
                return nil
            }
            return task
        }
        let frequentTasks = frequentRecentTasks(
            excluding: pinnedIDs,
            limit: LLMSuggestionInputPolicy.maximumCandidateCount
        )
        let priorityIDs = Set((pinnedTasks + frequentTasks).map(\.id))
        let remainingTasks = availableTasks
            .filter { !priorityIDs.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsPath = taskPath(for: lhs)
                let rhsPath = taskPath(for: rhs)
                let lhsKey = lhsPath.lowercased()
                let rhsKey = rhsPath.lowercased()
                if lhsKey != rhsKey { return lhsKey < rhsKey }
                if lhsPath != rhsPath { return lhsPath < rhsPath }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let candidateWindow = (pinnedTasks + frequentTasks + remainingTasks)
            .prefix(LLMSuggestionInputPolicy.maximumCandidateCount)

        return LLMSuggestionInputPolicy.boundedCandidates(
            candidateWindow
                .map { task in
                    LLMTaskCandidate(
                        id: task.id,
                        title: task.title,
                        path: taskPath(for: task),
                        iconName: ChecklistVisualSanitizer.sanitizedIcon(task.iconName),
                        colorHex: ChecklistVisualSanitizer.sanitizedColor(task.colorHex)
                    )
                }
        )
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
