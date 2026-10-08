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
}
