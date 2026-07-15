import Foundation

extension TimeTrackerStore {
    private static let maximumChecklistVisualSuggestionConcurrency = 3

    func autoSuggestChecklistVisualsIfNeeded() {
        guard canAutoSuggestChecklistVisuals else { return }
        let availableSlots = max(
            0,
            Self.maximumChecklistVisualSuggestionConcurrency - checklistVisualSuggestionInFlightIDs.count
        )
        guard availableSlots > 0 else { return }
        for item in checklistItemsNeedingVisualSuggestion().prefix(availableSlots) {
            suggestChecklistVisual(item, showsErrors: false)
        }
    }

    private func suggestChecklistVisual(_ item: ChecklistItem, showsErrors: Bool) {
        guard let request = checklistVisualSuggestionRequest(for: item) else { return }
        checklistVisualSuggestionFailureFingerprintByItemID[item.id] = nil
        checklistVisualSuggestionRetryAfterByItemID[item.id] = nil
        checklistVisualSuggestionInFlightIDs.insert(item.id)
        let requestID = UUID()
        let service = checklistVisualSuggestionService

        let task = Task { @MainActor [weak self] in
            do {
                let result = try await service.suggest(
                    checklistTitle: request.title,
                    taskTitle: request.taskTitle,
                    taskPath: request.taskPath,
                    endpoint: request.endpoint,
                    apiKey: request.apiKey,
                    modelID: request.modelID
                )
                try Task.checkCancellation()
                self?.completeChecklistVisualSuggestion(
                    result,
                    request: request,
                    requestID: requestID
                )
            } catch {
                self?.completeChecklistVisualSuggestionFailure(
                    error,
                    request: request,
                    requestID: requestID,
                    showsErrors: showsErrors,
                    wasCancelled: Task.isCancelled || error is CancellationError
                )
            }
        }
        checklistVisualSuggestionTasksByItemID[item.id] = StoreLLMSuggestionTask(
            requestID: requestID,
            isAutomatic: !showsErrors,
            task: task
        )
    }

    private func checklistVisualSuggestionRequest(for item: ChecklistItem) -> ChecklistVisualSuggestionRequest? {
        guard !checklistVisualSuggestionInFlightIDs.contains(item.id),
              let task = taskByID[item.taskID],
              isTaskAvailableForTracking(task) else {
            return nil
        }
        let policy = ChecklistVisualSuggestionPolicy()
        guard policy.shouldSuggest(item: item, visual: checklistVisual(for: item)) else { return nil }

        return ChecklistVisualSuggestionRequest(
            itemID: item.id,
            taskID: item.taskID,
            title: policy.normalizedTitle(item.title),
            taskTitle: task.title,
            taskPath: taskPath(for: task),
            endpoint: preferences.llmEndpoint,
            apiKey: preferences.llmAPIKey,
            modelID: preferences.llmSelectedModel
        )
    }

    private func completeChecklistVisualSuggestion(
        _ result: LLMChecklistVisualSuggestionResult,
        request: ChecklistVisualSuggestionRequest,
        requestID: UUID
    ) {
        guard isCurrentChecklistVisualSuggestionRequest(
            itemID: request.itemID,
            requestID: requestID
        ) else { return }
        defer {
            finishChecklistVisualSuggestionRequest(
                itemID: request.itemID,
                requestID: requestID
            )
        }

        let policy = ChecklistVisualSuggestionPolicy()
        guard matchesCurrentLLMConfiguration(
                  endpoint: request.endpoint,
                  apiKey: request.apiKey,
                  modelID: request.modelID
              ),
              preferences.llmAutomaticSuggestionsEnabled,
              let item = checklistItems.first(where: { $0.id == request.itemID }),
              item.taskID == request.taskID,
              item.deletedAt == nil,
              let task = taskByID[item.taskID],
              isTaskAvailableForTracking(task),
              policy.normalizedTitle(item.title) == request.title,
              policy.shouldSuggest(item: item, visual: checklistVisual(for: item)) else {
            return
        }

        _ = perform(event: .checklistChanged(taskID: item.taskID, affectedAncestorIDs: affectedAncestorIDs(for: item.taskID))) {
            guard let modelContext else { throw StoreError.notConfigured }
            try checklistCommandHandler.applyVisualSuggestion(
                item: item,
                result: result,
                existingVisual: checklistVisual(for: item),
                context: modelContext
            )
        }
    }

    private func completeChecklistVisualSuggestionFailure(
        _ error: Error,
        request: ChecklistVisualSuggestionRequest,
        requestID: UUID,
        showsErrors: Bool,
        wasCancelled: Bool
    ) {
        guard isCurrentChecklistVisualSuggestionRequest(
            itemID: request.itemID,
            requestID: requestID
        ) else { return }
        if wasCancelled {
            finishChecklistVisualSuggestionRequest(
                itemID: request.itemID,
                requestID: requestID,
                shouldAutoSuggest: false
            )
            return
        }
        defer {
            finishChecklistVisualSuggestionRequest(
                itemID: request.itemID,
                requestID: requestID
            )
        }

        guard matchesCurrentLLMConfiguration(
            endpoint: request.endpoint,
            apiKey: request.apiKey,
            modelID: request.modelID
        ), showsErrors || preferences.llmAutomaticSuggestionsEnabled else {
            return
        }
        if showsErrors {
            errorMessage = error.localizedDescription
        }
        checklistVisualSuggestionFailureFingerprintByItemID[request.itemID] = request.fingerprint
        checklistVisualSuggestionRetryAfterByItemID[request.itemID] = Date().addingTimeInterval(60)
    }

    private func finishChecklistVisualSuggestionRequest(
        itemID: UUID,
        requestID: UUID,
        shouldAutoSuggest: Bool = true
    ) {
        guard isCurrentChecklistVisualSuggestionRequest(
            itemID: itemID,
            requestID: requestID
        ) else { return }
        checklistVisualSuggestionTasksByItemID.removeValue(forKey: itemID)
        checklistVisualSuggestionInFlightIDs.remove(itemID)
        if shouldAutoSuggest {
            autoSuggestChecklistVisualsIfNeeded()
        }
    }

    func cancelAllChecklistVisualSuggestionRequests() {
        cancelChecklistVisualSuggestionRequests(for: checklistVisualSuggestionInFlightIDs)
    }

    func cancelChecklistVisualSuggestionRequests(matching requestIDsByItemID: [UUID: UUID]) {
        guard !requestIDsByItemID.isEmpty else { return }
        let matchingItemIDs = Set(
            checklistVisualSuggestionTasksByItemID.compactMap { itemID, request in
                requestIDsByItemID[itemID] == request.requestID ? itemID : nil
            }
        )
        cancelChecklistVisualSuggestionRequests(for: matchingItemIDs)
    }

    func cancelChecklistVisualSuggestionRequests(for itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty else { return }
        for itemID in itemIDs {
            guard let request = checklistVisualSuggestionTasksByItemID[itemID] else { continue }
            checklistVisualSuggestionTasksByItemID.removeValue(forKey: itemID)
            checklistVisualSuggestionInFlightIDs.remove(itemID)
            request.task.cancel()
        }
    }

    func cancelInvalidChecklistVisualSuggestionRequests() {
        let validItemIDs = Set(
            checklistItems.lazy
                .filter { item in
                    guard item.deletedAt == nil,
                          item.isCompleted == false,
                          let task = self.taskByID[item.taskID] else {
                        return false
                    }
                    return self.isTaskAvailableForTracking(task)
                }
                .map(\.id)
        )
        cancelChecklistVisualSuggestionRequests(
            for: checklistVisualSuggestionInFlightIDs.subtracting(validItemIDs)
        )
    }

    private func isCurrentChecklistVisualSuggestionRequest(
        itemID: UUID,
        requestID: UUID
    ) -> Bool {
        checklistVisualSuggestionTasksByItemID[itemID]?.requestID == requestID
    }

    private var canAutoSuggestChecklistVisuals: Bool {
        preferences.llmAutomaticSuggestionsEnabled &&
            preferences.llmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            preferences.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            preferences.llmSelectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func checklistItemsNeedingVisualSuggestion() -> [ChecklistItem] {
        let policy = ChecklistVisualSuggestionPolicy()
        let now = Date()
        return checklistItems.filter { item in
            guard !checklistVisualSuggestionInFlightIDs.contains(item.id),
                  taskByID[item.taskID] != nil,
                  policy.shouldSuggest(item: item, visual: checklistVisual(for: item)),
                  let request = checklistVisualSuggestionRequest(for: item) else {
                return false
            }
            let failedFingerprint = checklistVisualSuggestionFailureFingerprintByItemID[item.id]
            let retryAfter = checklistVisualSuggestionRetryAfterByItemID[item.id] ?? .distantPast
            return failedFingerprint != request.fingerprint || retryAfter <= now
        }
    }
}

private struct ChecklistVisualSuggestionRequest {
    let itemID: UUID
    let taskID: UUID
    let title: String
    let taskTitle: String
    let taskPath: String
    let endpoint: String
    let apiKey: String
    let modelID: String

    var fingerprint: String {
        [
            title,
            endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            modelID.trimmingCharacters(in: .whitespacesAndNewlines),
            String(apiKey.hashValue)
        ].joined(separator: "|")
    }
}
