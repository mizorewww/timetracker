import Foundation

extension TimeTrackerStore {
    @discardableResult
    func setPomodoroDefaultMode(_ value: String) -> Bool {
        setPreference(
            .pomodoroDefaultMode,
            valueJSON: PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroMode(value))
        )
    }

    @discardableResult
    func setDefaultFocusMinutes(_ value: Int) -> Bool {
        setPreference(.defaultFocusMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1 ... 480)))
    }

    @discardableResult
    func setDefaultBreakMinutes(_ value: Int) -> Bool {
        setPreference(.defaultBreakMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1 ... 480)))
    }

    @discardableResult
    func setDefaultPomodoroRounds(_ value: Int) -> Bool {
        setPreference(.defaultPomodoroRounds, valueJSON: PreferenceJSON.encode(value.clamped(to: 1 ... 24)))
    }

    @discardableResult
    func setPomodoroPlans(_ plans: [PomodoroPlan]) -> Bool {
        setPreference(
            .pomodoroPlans,
            valueJSON: PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroPlans(plans))
        )
    }

    @discardableResult
    func addPomodoroPlan() -> Bool {
        var plans = preferences.pomodoroPlans
        plans.append(.newPlan)
        return setPomodoroPlans(plans)
    }

    @discardableResult
    func updatePomodoroPlan(_ plan: PomodoroPlan) -> Bool {
        var plans = preferences.pomodoroPlans
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan.normalized()
        } else {
            plans.append(plan.normalized())
        }
        return setPomodoroPlans(plans)
    }

    @discardableResult
    func deletePomodoroPlan(id: UUID) -> Bool {
        setPomodoroPlans(preferences.pomodoroPlans.filter { $0.id != id })
    }
}
