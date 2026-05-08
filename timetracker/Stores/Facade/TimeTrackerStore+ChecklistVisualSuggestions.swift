import Foundation

extension TimeTrackerStore {
    func autoSuggestChecklistVisualsIfNeeded() {
        guard canAutoSuggestChecklistVisuals else { return }
        for item in checklistItemsNeedingVisualSuggestion().prefix(6) {
            suggestChecklistVisual(item, showsErrors: false)
        }
    }

    private func suggestChecklistVisual(_ item: ChecklistItem, showsErrors: Bool) {
        guard let request = checklistVisualSuggestionRequest(for: item) else { return }
        checklistVisualSuggestionInFlightIDs.insert(item.id)

        Task {
            do {
                let result = try await LLMChecklistVisualSuggestionService().suggest(
                    checklistTitle: request.title,
                    taskTitle: request.taskTitle,
                    taskPath: request.taskPath,
                    endpoint: request.endpoint,
                    apiKey: request.apiKey,
                    modelID: request.modelID
                )
                await MainActor.run {
                    applyChecklistVisualSuggestion(result, to: item, requestedTitle: request.title)
                }
            } catch {
                await MainActor.run {
                    finishChecklistVisualSuggestion(for: item.id, showsErrors: showsErrors, error: error)
                }
            }
        }
    }

    private func checklistVisualSuggestionRequest(for item: ChecklistItem) -> ChecklistVisualSuggestionRequest? {
        guard !checklistVisualSuggestionInFlightIDs.contains(item.id),
              let task = taskByID[item.taskID] else {
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
        requestedTitle: String
    ) {
        let policy = ChecklistVisualSuggestionPolicy()
        guard item.deletedAt == nil,
              policy.normalizedTitle(item.title) == requestedTitle,
              policy.shouldSuggest(item: item, visual: checklistVisual(for: item)) else {
            checklistVisualSuggestionInFlightIDs.remove(item.id)
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
    }

    private func finishChecklistVisualSuggestion(for itemID: UUID, showsErrors: Bool, error: Error) {
        if showsErrors {
            errorMessage = error.localizedDescription
        }
        checklistVisualSuggestionInFlightIDs.remove(itemID)
    }

    private var canAutoSuggestChecklistVisuals: Bool {
        preferences.llmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            preferences.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            preferences.llmSelectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func checklistItemsNeedingVisualSuggestion() -> [ChecklistItem] {
        let policy = ChecklistVisualSuggestionPolicy()
        return checklistItems.filter { item in
            !checklistVisualSuggestionInFlightIDs.contains(item.id) &&
                taskByID[item.taskID] != nil &&
                policy.shouldSuggest(item: item, visual: checklistVisual(for: item))
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
}
