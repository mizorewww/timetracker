import Foundation

extension TimeTrackerStore {
    func setPomodoroPlans(_ plans: [PomodoroPlan]) throws {
        try setPreference(
            .pomodoroPlans,
            valueJSON: PreferenceJSON.encode(AppPreferenceValueSanitizer.pomodoroPlans(plans))
        )
    }
}
