import Foundation

extension TimeTrackerStore {
    private static let maximumChecklistVisualSuggestionConcurrency = 3
    private static let checklistVisualSuggestionDebounceDelay:
        Duration = .milliseconds(350)

    func autoSuggestChecklistVisualsIfNeeded() {
        reconcileChecklistVisualSuggestionRequests()
        guard canAutoSuggestChecklistVisuals else { return }
        let availableSlots = max(
            0,
            Self.maximumChecklistVisualSuggestionConcurrency -
                checklistVisualSuggestionInFlightIDs.count -
                checklistVisualSuggestionDebounceTasksByItemID.count
        )
        guard availableSlots > 0 else { return }
        for item in checklistItemsNeedingVisualSuggestion().prefix(availableSlots) {
            scheduleChecklistVisualSuggestion(for: item)
        }
    }

    private func scheduleChecklistVisualSuggestion(for item: ChecklistItem) {
        guard checklistVisualSuggestionInFlightIDs.contains(item.id) == false,
              checklistVisualSuggestionDebounceTasksByItemID[item.id] == nil,
              let request = checklistVisualSuggestionRequest(for: item)
        else {
            return
        }
        let schedulingFingerprint = request.schedulingFingerprint
        let task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    for: Self.checklistVisualSuggestionDebounceDelay
                )
            } catch {
                return
            }
            self?.startScheduledChecklistVisualSuggestion(
                itemID: item.id,
                schedulingFingerprint: schedulingFingerprint
            )
        }
        checklistVisualSuggestionDebounceTasksByItemID[item.id] =
            StoreChecklistVisualSuggestionDebounceTask(
                schedulingFingerprint: schedulingFingerprint,
                task: task
            )
    }

    private func startScheduledChecklistVisualSuggestion(
        itemID: UUID,
        schedulingFingerprint: String
    ) {
        guard checklistVisualSuggestionDebounceTasksByItemID[itemID]?
            .schedulingFingerprint == schedulingFingerprint
        else {
            return
        }
        checklistVisualSuggestionDebounceTasksByItemID.removeValue(
            forKey: itemID
        )
        guard canAutoSuggestChecklistVisuals,
              let item = checklistItems.first(where: { $0.id == itemID }),
              let request = checklistVisualSuggestionRequest(for: item),
              request.schedulingFingerprint == schedulingFingerprint
        else {
            autoSuggestChecklistVisualsIfNeeded()
            return
        }
        suggestChecklistVisual(
            item,
            request: request,
            showsErrors: false
        )
    }

    private func suggestChecklistVisual(
        _ item: ChecklistItem,
        request: ChecklistVisualSuggestionRequest,
        showsErrors: Bool
    ) {
        guard checklistVisualSuggestionInFlightIDs.contains(item.id) == false
        else {
            return
        }
        checklistVisualSuggestionFailureFingerprintByItemID[item.id] = nil
        checklistVisualSuggestionRetryAfterByItemID[item.id] = nil
        checklistVisualSuggestionInFlightIDs.insert(item.id)
        checklistVisualSuggestionSchedulingFingerprintByItemID[item.id] =
            request.schedulingFingerprint
        let requestID = UUID()
        let service = checklistVisualSuggestionService

        let task = Task { @MainActor [weak self] in
            do {
                let result = try await service.suggest(
                    checklistTitle: request.title,
                    taskTitle: request.taskTitle,
                    taskPath: request.taskPath,
                    instructions: request.instructions,
                    endpoint: request.endpoint,
                    apiKey: request.apiKey,
                    modelID: request.modelID,
                    reasoningEffort: request.reasoningEffort
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
        guard let task = taskByID[item.taskID],
              isTaskEligibleAsParent(task)
        else {
            return nil
        }
        let policy = ChecklistVisualSuggestionPolicy()
        guard policy.shouldSuggest(item: item, visual: checklistVisual(for: item)) else { return nil }

        return ChecklistVisualSuggestionRequest(
            itemID: item.id,
            taskID: item.taskID,
            title: policy.normalizedTitle(item.title),
            baseline: ChecklistVisualSuggestionBaseline(
                item: item,
                visual: checklistVisual(for: item),
                normalizedTitle: policy.normalizedTitle(item.title)
            ),
            taskTitle: task.title,
            taskPath: taskPath(for: task),
            instructions: preferences.llmChecklistVisualInstructions,
            endpoint: preferences.llmEndpoint,
            apiKey: preferences.llmAPIKey,
            modelID: preferences.llmSelectedModel,
            reasoningEffort: preferences.llmReasoningEffort
        )
    }

    func cancelAllChecklistVisualSuggestionRequests() {
        cancelChecklistVisualSuggestionDebounceRequests(
            for: Set(checklistVisualSuggestionDebounceTasksByItemID.keys)
        )
        cancelChecklistVisualSuggestionRequests(for: checklistVisualSuggestionInFlightIDs)
        checklistVisualSuggestionFailureFingerprintByItemID.removeAll(
            keepingCapacity: false
        )
        checklistVisualSuggestionRetryAfterByItemID.removeAll(
            keepingCapacity: false
        )
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
            checklistVisualSuggestionSchedulingFingerprintByItemID.removeValue(
                forKey: itemID
            )
            request.task.cancel()
        }
    }

    private func cancelChecklistVisualSuggestionDebounceRequests(
        for itemIDs: Set<UUID>
    ) {
        guard itemIDs.isEmpty == false else { return }
        for itemID in itemIDs {
            guard let request =
                checklistVisualSuggestionDebounceTasksByItemID.removeValue(
                    forKey: itemID
                )
            else {
                continue
            }
            request.task.cancel()
        }
    }

    func cancelInvalidChecklistVisualSuggestionRequests() {
        let validItemIDs = Set(
            checklistItems.lazy
                .filter { item in
                    guard item.deletedAt == nil,
                          item.isCompleted == false,
                          let task = self.taskByID[item.taskID]
                    else {
                        return false
                    }
                    return self.isTaskEligibleAsParent(task)
                }
                .map(\.id)
        )
        cancelChecklistVisualSuggestionRequests(
            for: checklistVisualSuggestionInFlightIDs.subtracting(validItemIDs)
        )
        cancelChecklistVisualSuggestionDebounceRequests(
            for: Set(checklistVisualSuggestionDebounceTasksByItemID.keys)
                .subtracting(validItemIDs)
        )
        checklistVisualSuggestionFailureFingerprintByItemID =
            checklistVisualSuggestionFailureFingerprintByItemID.filter {
                validItemIDs.contains($0.key)
            }
        checklistVisualSuggestionRetryAfterByItemID =
            checklistVisualSuggestionRetryAfterByItemID.filter {
                validItemIDs.contains($0.key)
            }
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
                  checklistVisualSuggestionDebounceTasksByItemID[item.id] == nil,
                  taskByID[item.taskID] != nil,
                  policy.shouldSuggest(item: item, visual: checklistVisual(for: item)),
                  let request = checklistVisualSuggestionRequest(for: item)
            else {
                return false
            }
            let failedFingerprint = checklistVisualSuggestionFailureFingerprintByItemID[item.id]
            let retryAfter = checklistVisualSuggestionRetryAfterByItemID[item.id] ?? .distantPast
            return failedFingerprint != request.fingerprint || retryAfter <= now
        }
    }

    private func reconcileChecklistVisualSuggestionRequests() {
        let itemByID = Dictionary(
            uniqueKeysWithValues: checklistItems.map { ($0.id, $0) }
        )
        let supersededInFlightIDs = checklistVisualSuggestionInFlightIDs
            .filter { itemID in
                guard let item = itemByID[itemID],
                      let request = checklistVisualSuggestionRequest(for: item)
                else {
                    return true
                }
                return checklistVisualSuggestionSchedulingFingerprintByItemID[
                    itemID
                ] != request.schedulingFingerprint
            }
        cancelChecklistVisualSuggestionRequests(
            for: Set(supersededInFlightIDs)
        )

        let supersededDebounceIDs =
            checklistVisualSuggestionDebounceTasksByItemID.compactMap {
                itemID, pendingRequest in
                guard let item = itemByID[itemID],
                      let request = checklistVisualSuggestionRequest(for: item),
                      request.schedulingFingerprint ==
                      pendingRequest.schedulingFingerprint
                else {
                    return itemID
                }
                return nil
            }
        cancelChecklistVisualSuggestionDebounceRequests(
            for: Set(supersededDebounceIDs)
        )
    }
}
