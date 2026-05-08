#if os(macOS)
import SwiftUI

struct TimeTrackerCommands: Commands {
    @FocusedValue(\.newTaskAction) private var newTask
    @FocusedValue(\.manualTimeAction) private var manualTime
    @FocusedValue(\.startTimerAction) private var startTimer
    @FocusedValue(\.startPomodoroAction) private var startPomodoro
    @FocusedValue(\.refreshAction) private var refresh

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(AppStrings.newTask) {
                newTask?()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(newTask == nil)

            Button(AppStrings.addTime) {
                manualTime?()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(manualTime == nil)
        }

        CommandMenu(AppStrings.appName) {
            Button(AppStrings.newTask) {
                newTask?()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(newTask == nil)

            Button(AppStrings.addTime) {
                manualTime?()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(manualTime == nil)

            Divider()

            Button(AppStrings.localized("menu.startSelectedTask")) {
                startTimer?()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(startTimer == nil)

            Button(AppStrings.localized("menu.startPomodoro")) {
                startPomodoro?()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(startPomodoro == nil)

            Divider()

            Button(AppStrings.localized("menu.refreshData")) {
                refresh?()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(refresh == nil)
        }
    }
}
#endif
