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

        Task {
            do {
                let result = try await checklistVisualSuggestionService.suggest(
                    checklistTitle: request.title,
                    taskTitle: request.taskTitle,
                    taskPath: request.taskPath,
                    endpoint: request.endpoint,
                    apiKey: request.apiKey,
                    modelID: request.modelID
                )
                await MainActor.run {
                    applyChecklistVisualSuggestion(result, to: item, request: request)
                }
            } catch {
                await MainActor.run {
                    finishChecklistVisualSuggestion(
                        for: item.id,
                        request: request,
                        showsErrors: showsErrors,
                        error: error
                    )
                }
            }
        }
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
            title: policy.normalizedTitle(item.title),
            taskTitle: task.title,
            taskPath: taskPath(for: task),
            endpoint: preferences.llmEndpoint,
            apiKey: preferences.llmAPIKey,
            modelID: preferences.llmSelectedModel
        )
    }

    private func applyChecklistVisualSuggestion(
        _ result: LLMChecklistVisualSuggestionResult,
        to item: ChecklistItem,
        request: ChecklistVisualSuggestionRequest
    ) {
        let policy = ChecklistVisualSuggestionPolicy()
        guard matchesCurrentLLMConfiguration(
                  endpoint: request.endpoint,
                  apiKey: request.apiKey,
                  modelID: request.modelID
              ),
              preferences.llmAutomaticSuggestionsEnabled,
              item.deletedAt == nil,
              let task = taskByID[item.taskID],
              isTaskAvailableForTracking(task),
              policy.normalizedTitle(item.title) == request.title,
              policy.shouldSuggest(item: item, visual: checklistVisual(for: item)) else {
            checklistVisualSuggestionInFlightIDs.remove(item.id)
            autoSuggestChecklistVisualsIfNeeded()
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
        checklistVisualSuggestionInFlightIDs.remove(item.id)
        autoSuggestChecklistVisualsIfNeeded()
    }

    private func finishChecklistVisualSuggestion(
        for itemID: UUID,
        request: ChecklistVisualSuggestionRequest,
        showsErrors: Bool,
        error: Error
    ) {
        guard matchesCurrentLLMConfiguration(
            endpoint: request.endpoint,
            apiKey: request.apiKey,
            modelID: request.modelID
        ), showsErrors || preferences.llmAutomaticSuggestionsEnabled else {
            checklistVisualSuggestionInFlightIDs.remove(itemID)
            autoSuggestChecklistVisualsIfNeeded()
            return
        }
        if showsErrors {
            errorMessage = error.localizedDescription
        }
        checklistVisualSuggestionFailureFingerprintByItemID[itemID] = request.fingerprint
        checklistVisualSuggestionRetryAfterByItemID[itemID] = Date().addingTimeInterval(60)
        checklistVisualSuggestionInFlightIDs.remove(itemID)
        autoSuggestChecklistVisualsIfNeeded()
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
