import Foundation

extension TimeTrackerStore {
    func setPreferredColorScheme(_ value: String) {
        setPreference(
            .preferredColorScheme,
            valueJSON: PreferenceJSON.encode(AppPreferenceValueSanitizer.preferredColorScheme(value))
        )
    }

    func setPomodoroDefaultMode(_ value: String) {
        setPreference(.pomodoroDefaultMode, valueJSON: PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroMode(value)))
    }

    func setDefaultFocusMinutes(_ value: Int) {
        setPreference(.defaultFocusMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...480)))
    }

    func setDefaultBreakMinutes(_ value: Int) {
        setPreference(.defaultBreakMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...480)))
    }

    func setDefaultPomodoroRounds(_ value: Int) {
        setPreference(.defaultPomodoroRounds, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...24)))
    }

    func setPomodoroPlans(_ plans: [PomodoroPlan]) {
        setPreference(.pomodoroPlans, valueJSON: PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroPlans(plans)))
    }

    func addPomodoroPlan() {
        var plans = preferences.pomodoroPlans
        plans.append(.newPlan)
        setPomodoroPlans(plans)
    }

    func updatePomodoroPlan(_ plan: PomodoroPlan) {
        var plans = preferences.pomodoroPlans
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan.normalized()
        } else {
            plans.append(plan.normalized())
        }
        setPomodoroPlans(plans)
    }

    func deletePomodoroPlan(id: UUID) {
        setPomodoroPlans(preferences.pomodoroPlans.filter { $0.id != id })
    }

    func setAllowParallelTimers(_ value: Bool) {
        setPreference(.allowParallelTimers, valueJSON: PreferenceJSON.encode(value))
    }

    func setShowGrossAndWallTogether(_ value: Bool) {
        setPreference(.showGrossAndWallTogether, valueJSON: PreferenceJSON.encode(value))
    }

    @discardableResult
    func setCloudSyncEnabled(_ value: Bool) -> Bool {
        guard value != preferences.cloudSyncEnabled else { return true }
        if !value {
            UserDefaults.standard.set(false, forKey: AppCloudSync.enabledKey)
            preferences.cloudSyncEnabled = false
            return true
        }

        do {
            try writeAuthorization.requireUserWritesAllowed()
            guard let modelContext else { throw StoreError.notConfigured }
            UserDefaults.standard.set(true, forKey: AppCloudSync.enabledKey)
            preferences.cloudSyncEnabled = true
            if AppCloudSync.persistenceMode != AppCloudSync.modeICloud {
                _ = try syncConflictService.stageCurrentLocalSnapshotForCloudEnablement(
                    context: modelContext
                )
            }
            return true
        } catch {
            UserDefaults.standard.set(false, forKey: AppCloudSync.enabledKey)
            preferences.cloudSyncEnabled = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func setQuickStartTaskIDs(_ ids: [UUID]) -> Bool {
        let normalized = AppPreferenceValueSanitizer.quickStartTaskIDs(ids)
        return setPreference(.quickStartTaskIDs, valueJSON: PreferenceJSON.encode(normalized.map(\.uuidString)))
    }

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
            try writeAuthorization.requireUserWritesAllowed()
            try llmCredentialStore.writeAPIKey(value)
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

        let previousAPIKey: String?
        do {
            previousAPIKey = try llmCredentialStore.readAPIKey()
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        var credentialWasWritten = false
        let didCommit = perform(event: .preferenceChanged(key: nil)) {
            guard let modelContext else { throw StoreError.notConfigured }
            try llmCredentialStore.writeAPIKey(normalizedAPIKey)
            credentialWasWritten = true
            try preferenceCommandHandler.set(
                values: [
                    (.llmEndpoint, PreferenceJSON.encode(normalizedEndpoint)),
                    (.llmAvailableModelIDs, PreferenceJSON.encode(normalizedModels)),
                    (.llmSelectedModel, PreferenceJSON.encode(normalizedSelectedModel))
                ],
                context: modelContext
            )
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

    @discardableResult
    private func setPreference(_ key: AppPreferenceKey, valueJSON: String) -> Bool {
        perform(event: .preferenceChanged(key: key.rawValue)) {
            guard let modelContext else { throw StoreError.notConfigured }
            try preferenceCommandHandler.set(key: key, valueJSON: valueJSON, context: modelContext)
        }
    }
}
