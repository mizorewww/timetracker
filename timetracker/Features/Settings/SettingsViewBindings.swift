import SwiftUI

extension SettingsView {
    var pomodoroDefaultModeBinding: Binding<String> {
        Binding {
            store.preferences.pomodoroDefaultMode
        } set: { value in
            performSettingsMutation(title: SettingsCategory.focus.title) {
                try store.setPomodoroDefaultMode(value)
            }
        }
    }

    var defaultFocusMinutesBinding: Binding<Int> {
        Binding {
            store.preferences.defaultFocusMinutes
        } set: { value in
            performSettingsMutation(title: SettingsCategory.focus.title) {
                try store.setDefaultFocusMinutes(value)
                try store.setPomodoroDefaultMode(PomodoroPreset.custom.rawValue)
            }
        }
    }

    var defaultBreakMinutesBinding: Binding<Int> {
        Binding {
            store.preferences.defaultBreakMinutes
        } set: { value in
            performSettingsMutation(title: SettingsCategory.focus.title) {
                try store.setDefaultBreakMinutes(value)
                try store.setPomodoroDefaultMode(PomodoroPreset.custom.rawValue)
            }
        }
    }

    var defaultPomodoroRoundsBinding: Binding<Int> {
        Binding {
            store.preferences.defaultPomodoroRounds
        } set: { value in
            performSettingsMutation(title: SettingsCategory.focus.title) {
                try store.setDefaultPomodoroRounds(value)
            }
        }
    }

    var pomodoroPlansBinding: Binding<[PomodoroPlan]> {
        Binding {
            store.preferences.pomodoroPlans
        } set: { value in
            performSettingsMutation(title: SettingsCategory.focus.title) {
                try store.setPomodoroPlans(value)
            }
        }
    }

    var allowParallelTimersBinding: Binding<Bool> {
        Binding {
            store.preferences.allowParallelTimers
        } set: { value in
            performSettingsMutation(title: SettingsCategory.general.title) {
                try store.setAllowParallelTimers(value)
            }
        }
    }

    var showGrossAndWallTogetherBinding: Binding<Bool> {
        Binding {
            store.preferences.showGrossAndWallTogether
        } set: { value in
            performSettingsMutation(title: SettingsCategory.general.title) {
                try store.setShowGrossAndWallTogether(value)
            }
        }
    }

    var cloudSyncEnabledBinding: Binding<Bool> {
        Binding {
            store.preferences.cloudSyncEnabled
        } set: { value in
            store.setCloudSyncEnabled(value)
        }
    }

    var llmAutomaticSuggestionsEnabledBinding: Binding<Bool> {
        Binding {
            store.preferences.llmAutomaticSuggestionsEnabled
        } set: { value in
            store.setLLMAutomaticSuggestionsEnabled(value)
        }
    }
}
