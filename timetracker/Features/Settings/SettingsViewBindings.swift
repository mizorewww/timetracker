import SwiftUI

extension SettingsView {
    var pomodoroDefaultModeBinding: Binding<String> {
        Binding {
            store.preferences.pomodoroDefaultMode
        } set: { value in
            handleSettingsStoreMutation(
                store.setPomodoroDefaultMode(value),
                title: SettingsCategory.focus.title
            )
        }
    }

    var defaultFocusMinutesBinding: Binding<Int> {
        Binding {
            store.preferences.defaultFocusMinutes
        } set: { value in
            let minutesSaved = store.setDefaultFocusMinutes(value)
            let modeSaved = store.setPomodoroDefaultMode(PomodoroPreset.custom.rawValue)
            handleSettingsStoreMutation(
                minutesSaved && modeSaved,
                title: SettingsCategory.focus.title
            )
        }
    }

    var defaultBreakMinutesBinding: Binding<Int> {
        Binding {
            store.preferences.defaultBreakMinutes
        } set: { value in
            let minutesSaved = store.setDefaultBreakMinutes(value)
            let modeSaved = store.setPomodoroDefaultMode(PomodoroPreset.custom.rawValue)
            handleSettingsStoreMutation(
                minutesSaved && modeSaved,
                title: SettingsCategory.focus.title
            )
        }
    }

    var defaultPomodoroRoundsBinding: Binding<Int> {
        Binding {
            store.preferences.defaultPomodoroRounds
        } set: { value in
            handleSettingsStoreMutation(
                store.setDefaultPomodoroRounds(value),
                title: SettingsCategory.focus.title
            )
        }
    }

    var pomodoroPlansBinding: Binding<[PomodoroPlan]> {
        Binding {
            store.preferences.pomodoroPlans
        } set: { value in
            handleSettingsStoreMutation(
                store.setPomodoroPlans(value),
                title: SettingsCategory.focus.title
            )
        }
    }

    var allowParallelTimersBinding: Binding<Bool> {
        Binding {
            store.preferences.allowParallelTimers
        } set: { value in
            handleSettingsStoreMutation(
                store.setAllowParallelTimers(value),
                title: SettingsCategory.general.title
            )
        }
    }

    var showGrossAndWallTogetherBinding: Binding<Bool> {
        Binding {
            store.preferences.showGrossAndWallTogether
        } set: { value in
            handleSettingsStoreMutation(
                store.setShowGrossAndWallTogether(value),
                title: SettingsCategory.general.title
            )
        }
    }

    var cloudSyncEnabledBinding: Binding<Bool> {
        Binding {
            store.preferences.cloudSyncEnabled
        } set: { value in
            handleSettingsStoreMutation(
                store.setCloudSyncEnabled(value),
                title: SettingsCategory.dataAndSync.title
            )
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
