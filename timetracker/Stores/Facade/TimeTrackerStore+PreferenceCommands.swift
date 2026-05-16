import Foundation

extension TimeTrackerStore {
    func setPreferredColorScheme(_ value: String) {
        setPreference(.preferredColorScheme, valueJSON: PreferenceJSON.encode(value))
    }

    func setPomodoroDefaultMode(_ value: String) {
        setPreference(.pomodoroDefaultMode, valueJSON: PreferenceJSON.encode(value))
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
        setPreference(.pomodoroPlans, valueJSON: PreferenceJSON.encode(plans.map { $0.normalized() }))
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

    func setCloudSyncEnabled(_ value: Bool) {
        setPreference(.cloudSyncEnabled, valueJSON: PreferenceJSON.encode(value))
        UserDefaults.standard.set(value, forKey: AppCloudSync.enabledKey)
    }

    func setQuickStartTaskIDs(_ ids: [UUID]) {
        setPreference(.quickStartTaskIDs, valueJSON: PreferenceJSON.encode(ids.map(\.uuidString)))
    }

    func setLLMEndpoint(_ value: String) {
        setPreference(.llmEndpoint, valueJSON: PreferenceJSON.encode(value.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func setLLMAPIKey(_ value: String) {
        setPreference(.llmAPIKey, valueJSON: PreferenceJSON.encode(value.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func setLLMSelectedModel(_ value: String) {
        setPreference(.llmSelectedModel, valueJSON: PreferenceJSON.encode(value))
    }

    func setLLMAvailableModelIDs(_ values: [String]) {
        let normalized = Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        setPreference(.llmAvailableModelIDs, valueJSON: PreferenceJSON.encode(normalized))
    }

    private func setPreference(_ key: AppPreferenceKey, valueJSON: String) {
        perform(event: .preferenceChanged(key: key.rawValue)) {
            guard let modelContext else { throw StoreError.notConfigured }
            try preferenceCommandHandler.set(key: key, valueJSON: valueJSON, context: modelContext)
        }
    }
}
