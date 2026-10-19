import Foundation
import SwiftData

extension TimeTrackerStore {
    func setLLMAutomaticSuggestionsEnabled(_ value: Bool) {
        AppDefaults.shared.set(value, forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled)
        preferences.llmAutomaticSuggestionsEnabled = value
        if value {
            autoSuggestInboxItemsIfNeeded()
            autoSuggestChecklistVisualsIfNeeded()
        } else {
            cancelAutomaticInboxSuggestionRequests()
            cancelAllChecklistVisualSuggestionRequests()
        }
    }

    func setLLMPromptInstructions(
        _ value: String,
        for kind: LLMPromptKind
    ) throws {
        let normalized = try AppPreferenceValueSanitizer.llmPromptInstructions(
            value,
            for: kind
        )
        let changed = normalized != preferences.llmInstructions(for: kind)
        let inboxRequestSnapshot = inboxSuggestionLifecycle.requestSnapshot()
        let checklistRequestSnapshot = checklistVisualSuggestionLifecycle
            .requestSnapshot()
        let preferenceKey: AppPreferenceKey = switch kind {
        case .inboxRouting:
            .llmInboxSuggestionInstructions
        case .checklistVisual:
            .llmChecklistVisualInstructions
        case .taskPlan:
            .llmTaskPlanInstructions
        }
        try setPreference(
            preferenceKey,
            valueJSON: PreferenceJSON.encode(normalized)
        )
        guard changed else { return }
        switch kind {
        case .inboxRouting:
            cancelInboxSuggestionRequests(matching: inboxRequestSnapshot)
        case .checklistVisual:
            cancelChecklistVisualSuggestionRequests(
                matching: checklistRequestSnapshot
            )
        case .taskPlan:
            break
        }
    }

    func setLLMConfiguration(
        endpoint: String,
        apiKey: String,
        selectedModel: String,
        availableModelIDs: [String],
        reasoningEffort: LLMReasoningEffort
    ) throws {
        let normalizedEndpoint = AppPreferenceValueSanitizer.llmEndpoint(endpoint)
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelectedModel = AppPreferenceValueSanitizer.llmModelID(selectedModel)
        let normalizedModels = AppPreferenceValueSanitizer.llmModelIDs(availableModelIDs)
        guard LLMClient.isValidEndpoint(normalizedEndpoint),
              !normalizedAPIKey.isEmpty,
              normalizedModels.contains(normalizedSelectedModel)
        else {
            throw StoreError.llmConfigurationIncomplete
        }
        let configurationChanged = !matchesCurrentLLMConfiguration(
            LLMRequestConfiguration(
                endpoint: normalizedEndpoint,
                apiKey: normalizedAPIKey,
                modelID: normalizedSelectedModel,
                reasoningEffort: reasoningEffort
            )
        )
        let taskSnapshot = llmSuggestionTaskSnapshot()

        var previousAPIKey: String?
        var credentialWasWritten = false
        do {
            try StoreScopedPreferenceCommandCoordinator(
                session: requireMutationSession()
            ).set(
                values: [
                    (.llmEndpoint, PreferenceJSON.encode(normalizedEndpoint)),
                    (.llmAvailableModelIDs, PreferenceJSON.encode(normalizedModels)),
                    (.llmSelectedModel, PreferenceJSON.encode(normalizedSelectedModel)),
                    (
                        .llmReasoningEffort,
                        PreferenceJSON.encode(reasoningEffort.rawValue)
                    ),
                ],
                applyingLocalMutation: {
                    previousAPIKey = try llmCredentialStore.readAPIKey()
                    try llmCredentialStore.writeAPIKey(normalizedAPIKey)
                    credentialWasWritten = true
                }
            )
            finishStoreScopedMutation(events: [.preferenceChanged(key: nil)])
        } catch {
            if credentialWasWritten {
                // Report the save failure; a failed key restore only leaves the
                // new key in place, which the user is re-entering anyway.
                try? llmCredentialStore.writeAPIKey(previousAPIKey ?? "")
            }
            throw error
        }

        if configurationChanged {
            cancelLLMSuggestionTasks(matching: taskSnapshot)
        }
        inboxSuggestionFailureByItemID.removeAll(keepingCapacity: true)
        if matchesCurrentLLMConfiguration(
            LLMRequestConfiguration(
                endpoint: normalizedEndpoint,
                apiKey: normalizedAPIKey,
                modelID: normalizedSelectedModel,
                reasoningEffort: reasoningEffort
            )
        ) {
            autoSuggestInboxItemsIfNeeded()
            autoSuggestChecklistVisualsIfNeeded()
        }
    }

    private func llmSuggestionTaskSnapshot() -> LLMSuggestionTaskSnapshot {
        LLMSuggestionTaskSnapshot(
            inboxRequestIDsByItemID: inboxSuggestionLifecycle.requestSnapshot(),
            checklistRequestIDsByItemID: checklistVisualSuggestionLifecycle.requestSnapshot()
        )
    }

    private func cancelLLMSuggestionTasks(matching snapshot: LLMSuggestionTaskSnapshot) {
        cancelInboxSuggestionRequests(matching: snapshot.inboxRequestIDsByItemID)
        cancelChecklistVisualSuggestionRequests(matching: snapshot.checklistRequestIDsByItemID)
    }
}
