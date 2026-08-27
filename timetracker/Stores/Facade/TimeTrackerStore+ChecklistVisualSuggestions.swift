import Foundation

extension TimeTrackerStore {
    private static let checklistVisualSuggestionDebounceDelay:
        Duration = .milliseconds(350)

    func autoSuggestChecklistVisualsIfNeeded() {
        reconcileChecklistVisualSuggestionRequests()
        guard canAutoSuggestLLMSuggestions else { return }
        let availableSlots = checklistVisualSuggestionLifecycle.debouncedAvailableSlots
        guard availableSlots > 0 else { return }
        for item in checklistItemsNeedingVisualSuggestion().prefix(availableSlots) {
            scheduleChecklistVisualSuggestion(for: item)
        }
    }

    private func scheduleChecklistVisualSuggestion(for item: ChecklistItem) {
        guard checklistVisualSuggestionLifecycle.inFlightIDs.contains(item.id) == false,
              checklistVisualSuggestionLifecycle.debounceTasksByItemID[item.id] == nil,
              let request = checklistVisualSuggestionRequest(for: item)
        else {
            return
        }
        checklistVisualSuggestionLifecycle.scheduleDebounce(
            itemID: item.id,
            fingerprint: request.schedulingFingerprint,
            delay: Self.checklistVisualSuggestionDebounceDelay
        ) { [weak self] itemID, schedulingFingerprint in
            self?.startScheduledChecklistVisualSuggestion(
                itemID: itemID,
                schedulingFingerprint: schedulingFingerprint
            )
        }
    }

    private func startScheduledChecklistVisualSuggestion(
        itemID: UUID,
        schedulingFingerprint: String
    ) {
        guard checklistVisualSuggestionLifecycle.finishDebounce(
            itemID: itemID,
            fingerprint: schedulingFingerprint
        ) else {
            return
        }
        guard canAutoSuggestLLMSuggestions,
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
        guard checklistVisualSuggestionLifecycle.inFlightIDs.contains(item.id) == false
        else {
            return
        }
        checklistVisualSuggestionLifecycle.failureByItemID[item.id] = nil
        checklistVisualSuggestionSchedulingFingerprintByItemID[item.id] =
            request.schedulingFingerprint
        let service = checklistVisualSuggestionService

        checklistVisualSuggestionLifecycle.start(
            itemID: item.id,
            isAutomatic: !showsErrors,
            perform: {
                try await service.suggest(
                    checklistTitle: request.title,
                    taskTitle: request.taskTitle,
                    taskPath: request.taskPath,
                    instructions: request.instructions,
                    configuration: request.configuration
                )
            },
            onSuccess: { [weak self] result, requestID in
                self?.completeChecklistVisualSuggestion(
                    result,
                    request: request,
                    requestID: requestID
                )
            },
            onFailure: { [weak self] error, requestID, wasCancelled in
                self?.completeChecklistVisualSuggestionFailure(
                    error,
                    request: request,
                    requestID: requestID,
                    showsErrors: showsErrors,
                    wasCancelled: wasCancelled
                )
            }
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
            configuration: preferences.llmRequestConfiguration
        )
    }

    func cancelAllChecklistVisualSuggestionRequests() {
        checklistVisualSuggestionLifecycle.cancelDebounce(
            for: Set(checklistVisualSuggestionLifecycle.debounceTasksByItemID.keys)
        )
        checklistVisualSuggestionLifecycle.cancelInFlight(
            for: checklistVisualSuggestionLifecycle.inFlightIDs
        ) { itemID in
            checklistVisualSuggestionSchedulingFingerprintByItemID.removeValue(
                forKey: itemID
            )
        }
        checklistVisualSuggestionLifecycle.failureByItemID.removeAll(
            keepingCapacity: false
        )
    }

    func cancelChecklistVisualSuggestionRequests(matching requestIDsByItemID: [UUID: UUID]) {
        guard !requestIDsByItemID.isEmpty else { return }
        let matchingItemIDs = Set(
            checklistVisualSuggestionLifecycle.tasksByItemID.compactMap { itemID, request in
                requestIDsByItemID[itemID] == request.requestID ? itemID : nil
            }
        )
        cancelChecklistVisualSuggestionRequests(for: matchingItemIDs)
    }

    func cancelChecklistVisualSuggestionRequests(for itemIDs: Set<UUID>) {
        guard !itemIDs.isEmpty else { return }
        checklistVisualSuggestionLifecycle.cancelInFlight(for: itemIDs) { itemID in
            checklistVisualSuggestionSchedulingFingerprintByItemID.removeValue(
                forKey: itemID
            )
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
            for: checklistVisualSuggestionLifecycle.inFlightIDs.subtracting(validItemIDs)
        )
        checklistVisualSuggestionLifecycle.cancelDebounce(
            for: Set(checklistVisualSuggestionLifecycle.debounceTasksByItemID.keys)
                .subtracting(validItemIDs)
        )
        checklistVisualSuggestionLifecycle.failureByItemID =
            checklistVisualSuggestionLifecycle.failureByItemID.filter {
                validItemIDs.contains($0.key)
            }
    }

    private func checklistItemsNeedingVisualSuggestion() -> [ChecklistItem] {
        let policy = ChecklistVisualSuggestionPolicy()
        let now = Date()
        return checklistItems.filter { item in
            guard !checklistVisualSuggestionLifecycle.inFlightIDs.contains(item.id),
                  checklistVisualSuggestionLifecycle.debounceTasksByItemID[item.id] == nil,
                  taskByID[item.taskID] != nil,
                  policy.shouldSuggest(item: item, visual: checklistVisual(for: item)),
                  let request = checklistVisualSuggestionRequest(for: item)
            else {
                return false
            }
            let failure = checklistVisualSuggestionLifecycle.failureByItemID[item.id]
            let retryAfter = failure?.retryAfter ?? .distantPast
            return failure?.fingerprint != request.fingerprint || retryAfter <= now
        }
    }

    private func reconcileChecklistVisualSuggestionRequests() {
        let itemByID = Dictionary(
            uniqueKeysWithValues: checklistItems.map { ($0.id, $0) }
        )
        let supersededInFlightIDs = checklistVisualSuggestionLifecycle.inFlightIDs
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
            checklistVisualSuggestionLifecycle.debounceTasksByItemID.compactMap {
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
        checklistVisualSuggestionLifecycle.cancelDebounce(
            for: Set(supersededDebounceIDs)
        )
    }
}
