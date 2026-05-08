import SwiftUI

extension SettingsView {
    var preferredColorSchemeBinding: Binding<String> {
        Binding {
            store.preferences.preferredColorScheme
        } set: { value in
            store.setPreferredColorScheme(value)
        }
    }

    var pomodoroDefaultModeBinding: Binding<String> {
        Binding {
            store.preferences.pomodoroDefaultMode
        } set: { value in
            store.setPomodoroDefaultMode(value)
        }
    }

    var defaultFocusMinutesBinding: Binding<Int> {
        Binding {
            store.preferences.defaultFocusMinutes
        } set: { value in
            store.setDefaultFocusMinutes(value)
            store.setPomodoroDefaultMode(PomodoroPreset.custom.rawValue)
        }
    }

    var defaultBreakMinutesBinding: Binding<Int> {
        Binding {
            store.preferences.defaultBreakMinutes
        } set: { value in
            store.setDefaultBreakMinutes(value)
            store.setPomodoroDefaultMode(PomodoroPreset.custom.rawValue)
        }
    }

    var defaultPomodoroRoundsBinding: Binding<Int> {
        Binding {
            store.preferences.defaultPomodoroRounds
        } set: { value in
            store.setDefaultPomodoroRounds(value)
        }
    }

    var allowParallelTimersBinding: Binding<Bool> {
        Binding {
            store.preferences.allowParallelTimers
        } set: { value in
            store.setAllowParallelTimers(value)
        }
    }

    var showGrossAndWallTogetherBinding: Binding<Bool> {
        Binding {
            store.preferences.showGrossAndWallTogether
        } set: { value in
            store.setShowGrossAndWallTogether(value)
        }
    }

    var cloudSyncEnabledBinding: Binding<Bool> {
        Binding {
            store.preferences.cloudSyncEnabled
        } set: { value in
            store.setCloudSyncEnabled(value)
        }
    }

    var llmEndpointBinding: Binding<String> {
        Binding {
            store.preferences.llmEndpoint
        } set: { value in
            store.setLLMEndpoint(value)
        }
    }

    var llmAPIKeyBinding: Binding<String> {
        Binding {
            store.preferences.llmAPIKey
        } set: { value in
            store.setLLMAPIKey(value)
        }
    }

    var llmSelectedModelBinding: Binding<String> {
        Binding {
            store.preferences.llmSelectedModel
        } set: { value in
            store.setLLMSelectedModel(value)
        }
    }
}
