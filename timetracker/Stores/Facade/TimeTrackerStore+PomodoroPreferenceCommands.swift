import Foundation

extension TimeTrackerStore {
    func setPomodoroDefaultMode(_ value: String) throws {
        try setPreference(
            .pomodoroDefaultMode,
            valueJSON: PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroMode(value))
        )
    }

    func setDefaultFocusMinutes(_ value: Int) throws {
        try setPreference(.defaultFocusMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1 ... 480)))
    }

    func setDefaultBreakMinutes(_ value: Int) throws {
        try setPreference(.defaultBreakMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1 ... 480)))
    }

    func setDefaultPomodoroRounds(_ value: Int) throws {
        try setPreference(.defaultPomodoroRounds, valueJSON: PreferenceJSON.encode(value.clamped(to: 1 ... 24)))
    }

    func setPomodoroPlans(_ plans: [PomodoroPlan]) throws {
        try setPreference(
            .pomodoroPlans,
            valueJSON: PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroPlans(plans))
        )
    }
}
