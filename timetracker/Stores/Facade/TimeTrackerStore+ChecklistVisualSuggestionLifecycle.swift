import Foundation

extension TimeTrackerStore {
    func completeChecklistVisualSuggestion(
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

    func completeChecklistVisualSuggestionFailure(
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

    private func isCurrentChecklistVisualSuggestionRequest(
        itemID: UUID,
        requestID: UUID
    ) -> Bool {
        checklistVisualSuggestionTasksByItemID[itemID]?.requestID == requestID
    }
}

struct ChecklistVisualSuggestionRequest {
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
