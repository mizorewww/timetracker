import Foundation

extension TimeTrackerStore {
    func toggleChecklistItem(_ item: ChecklistItem) {
        perform(event: .checklistChanged(taskID: item.taskID, affectedAncestorIDs: affectedAncestorIDs(for: item.taskID))) {
            guard let modelContext else { throw StoreError.notConfigured }
            try checklistCommandHandler.toggle(item, context: modelContext)
        }
    }

    func addChecklistItem(taskID: UUID, title: String) {
        perform(event: .checklistChanged(taskID: taskID, affectedAncestorIDs: affectedAncestorIDs(for: taskID))) {
            guard let modelContext else { throw StoreError.notConfigured }
            try checklistCommandHandler.add(
                taskID: taskID,
                title: title,
                existingItems: checklistItems(for: taskID),
                context: modelContext
            )
        }
    }

    func reorderChecklistItems(taskID: UUID, sourceOffsets: IndexSet, destination: Int) {
        let orderedItems = checklistItems(for: taskID).sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.sortOrder < rhs.sortOrder
        }
        guard let orderedIDs = checklistCommandHandler.reorderedIDs(
            items: orderedItems,
            sourceOffsets: sourceOffsets,
            destination: destination
        ) else {
            return
        }

        perform(event: .checklistChanged(taskID: taskID, affectedAncestorIDs: affectedAncestorIDs(for: taskID))) {
            guard let modelContext else { throw StoreError.notConfigured }
            try checklistCommandHandler.reorder(
                taskID: taskID,
                orderedItemIDs: orderedIDs,
                context: modelContext
            )
        }
    }

    func autoSuggestChecklistVisualsIfNeeded() {
        guard canAutoSuggestChecklistVisuals else { return }
        for item in checklistItemsNeedingVisualSuggestion().prefix(6) {
            suggestChecklistVisual(item, showsErrors: false)
        }
    }

    private func suggestChecklistVisual(_ item: ChecklistItem, showsErrors: Bool) {
        guard !checklistVisualSuggestionInFlightIDs.contains(item.id),
              let task = taskByID[item.taskID] else {
            return
        }
        let visual = checklistVisual(for: item)
        guard ChecklistVisualSuggestionPolicy().shouldSuggest(item: item, visual: visual) else { return }

        let endpoint = preferences.llmEndpoint
        let apiKey = preferences.llmAPIKey
        let modelID = preferences.llmSelectedModel
        let requestedTitle = ChecklistVisualSuggestionPolicy().normalizedTitle(item.title)
        let taskTitle = task.title
        let resolvedTaskPath = taskPath(for: task)
        checklistVisualSuggestionInFlightIDs.insert(item.id)

        Task {
            do {
                let result = try await LLMChecklistVisualSuggestionService().suggest(
                    checklistTitle: requestedTitle,
                    taskTitle: taskTitle,
                    taskPath: resolvedTaskPath,
                    endpoint: endpoint,
                    apiKey: apiKey,
                    modelID: modelID
                )
                await MainActor.run {
                    guard item.deletedAt == nil,
                          ChecklistVisualSuggestionPolicy().normalizedTitle(item.title) == requestedTitle,
                          ChecklistVisualSuggestionPolicy().shouldSuggest(item: item, visual: checklistVisual(for: item)) else {
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
            } catch {
                await MainActor.run {
                    if showsErrors {
                        errorMessage = error.localizedDescription
                    }
                    checklistVisualSuggestionInFlightIDs.remove(item.id)
                }
            }
        }
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
