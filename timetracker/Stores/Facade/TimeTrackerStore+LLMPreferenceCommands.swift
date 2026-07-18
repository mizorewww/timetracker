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
        UserDefaults.standard.set(value, forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled)
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
    func setLLMTaskPlanInstructions(_ value: String) -> Bool {
        do {
            let normalized = try AppPreferenceValueSanitizer.llmTaskPlanInstructions(value)
            return setPreference(
                .llmTaskPlanInstructions,
                valueJSON: PreferenceJSON.encode(normalized)
            )
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func setLLMConfiguration(
        endpoint: String,
        apiKey: String,
        selectedModel: String,
        availableModelIDs: [String]
    ) -> Bool {
        let normalizedEndpoint = AppPreferenceValueSanitizer.llmEndpoint(endpoint)
        let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelectedModel = AppPreferenceValueSanitizer.llmModelID(selectedModel)
        let normalizedModels = AppPreferenceValueSanitizer.llmModelIDs(availableModelIDs)
        guard LLMModelService.modelsURL(endpoint: normalizedEndpoint) != nil,
              !normalizedAPIKey.isEmpty,
              normalizedModels.contains(normalizedSelectedModel) else {
            errorMessage = AppStrings.localized("settings.llm.needsSetup")
            return false
        }
        let configurationChanged = !matchesCurrentLLMConfiguration(
            endpoint: normalizedEndpoint,
            apiKey: normalizedAPIKey,
            modelID: normalizedSelectedModel
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
                    (.llmSelectedModel, PreferenceJSON.encode(normalizedSelectedModel))
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
                endpoint: normalizedEndpoint,
                apiKey: normalizedAPIKey,
                modelID: normalizedSelectedModel
            ) {
                autoSuggestInboxItemsIfNeeded()
                autoSuggestChecklistVisualsIfNeeded()
            }
        }
        return didCommit
    }

    private func llmSuggestionTaskSnapshot() -> LLMSuggestionTaskSnapshot {
        LLMSuggestionTaskSnapshot(
            inboxRequestIDsByItemID: inboxSuggestionTasksByItemID.mapValues(\.requestID),
            checklistRequestIDsByItemID: checklistVisualSuggestionTasksByItemID.mapValues(\.requestID)
        )
    }

    private func cancelLLMSuggestionTasks(matching snapshot: LLMSuggestionTaskSnapshot) {
        cancelInboxSuggestionRequests(matching: snapshot.inboxRequestIDsByItemID)
        cancelChecklistVisualSuggestionRequests(matching: snapshot.checklistRequestIDsByItemID)
    }
}
