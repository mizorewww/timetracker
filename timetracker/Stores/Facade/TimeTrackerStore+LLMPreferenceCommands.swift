import Foundation
import SwiftData

extension TimeTrackerStore {
    func setLLMEndpoint(_ value: String) {
        let normalized = AppPreferenceValueSanitizer.llmEndpoint(value)
        let changed = normalized != AppPreferenceValueSanitizer.llmEndpoint(preferences.llmEndpoint)
        let taskSnapshot = llmSuggestionTaskSnapshot()
        let didSet = setPreference(.llmEndpoint, valueJSON: PreferenceJSON.encode(normalized))
        if didSet, changed {
            cancelLLMSuggestionTasks(matching: taskSnapshot)
        }
    }

    func setLLMAPIKey(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = normalized != preferences.llmAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskSnapshot = llmSuggestionTaskSnapshot()
        do {
            guard let modelContext else { throw StoreError.notConfigured }
            try StoreScopedPreferenceCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
            ).withLockedStoreAccess {
                try llmCredentialStore.writeAPIKey(value)
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        do {
            let event = StoreDomainEvent.preferenceChanged(key: SyncedPreferenceService.legacyLLMAPIKey)
            try refresh(plan: refreshPlanner.plan(after: [event]))
        } catch {
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                error.localizedDescription
            )
        }
        if changed {
            cancelLLMSuggestionTasks(matching: taskSnapshot)
        }
    }

    func setLLMSelectedModel(_ value: String) {
        let normalized = AppPreferenceValueSanitizer.llmModelID(value)
        let changed = normalized != AppPreferenceValueSanitizer.llmModelID(preferences.llmSelectedModel)
        let taskSnapshot = llmSuggestionTaskSnapshot()
        let didSet = setPreference(.llmSelectedModel, valueJSON: PreferenceJSON.encode(normalized))
        if didSet, changed {
            cancelLLMSuggestionTasks(matching: taskSnapshot)
        }
    }

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

    func setLLMAvailableModelIDs(_ values: [String]) {
        let normalized = AppPreferenceValueSanitizer.llmModelIDs(values)
        setPreference(.llmAvailableModelIDs, valueJSON: PreferenceJSON.encode(normalized))
    }

    @discardableResult
    func setLLMPromptInstructions(
        _ value: String,
        for kind: LLMPromptKind
    ) -> Bool {
        do {
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
            let didSet = setPreference(
                preferenceKey,
                valueJSON: PreferenceJSON.encode(normalized)
            )
            if didSet, changed {
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
            return didSet
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func setLLMTaskPlanInstructions(_ value: String) -> Bool {
        setLLMPromptInstructions(value, for: .taskPlan)
    }

    @discardableResult
    func setLLMConfiguration(
        endpoint: String,
        apiKey: String,
        selectedModel: String,
        availableModelIDs: [String],
        reasoningEffort: LLMReasoningEffort
    ) -> Bool {
        let normalizedEndpoint = AppPreferenceValueSanitizer.llmEndpoint(endpoint)
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelectedModel = AppPreferenceValueSanitizer.llmModelID(selectedModel)
        let normalizedModels = AppPreferenceValueSanitizer.llmModelIDs(availableModelIDs)
        guard LLMModelService.modelsURL(endpoint: normalizedEndpoint) != nil,
              !normalizedAPIKey.isEmpty,
              normalizedModels.contains(normalizedSelectedModel)
        else {
            errorMessage = AppStrings.localized("settings.llm.needsSetup")
            return false
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
        let didCommit: Bool
        do {
            guard let modelContext else { throw StoreError.notConfigured }
            try StoreScopedPreferenceCommandCoordinator(
                container: modelContext.container,
                writeAuthorization: writeAuthorization
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
            didCommit = true
        } catch {
            errorMessage = error.localizedDescription
            didCommit = false
        }

        if !didCommit, credentialWasWritten {
            do {
                try llmCredentialStore.writeAPIKey(previousAPIKey ?? "")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if didCommit {
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
        return didCommit
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
