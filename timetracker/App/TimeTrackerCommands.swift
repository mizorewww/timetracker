#if os(macOS)
import SwiftUI

struct TimeTrackerCommands: Commands {
    @FocusedValue(\.timeTrackerStore) private var store

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(AppStrings.newTask) {
                store?.presentNewTask()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(store == nil)

            Button(AppStrings.addTime) {
                store?.presentManualTime()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(store == nil)

            Divider()

            Button(AppStrings.localized("menu.startSelectedTask")) {
                store?.startSelectedTask()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(store?.selectedTask == nil)

            Button(AppStrings.localized("menu.startPomodoro")) {
                store?.startPomodoroForSelectedTask()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(store?.selectedTask == nil)
        }

        CommandGroup(after: .sidebar) {
            Divider()

            destinationButton(.today, key: "1")
            destinationButton(.inbox, key: "2")
            destinationButton(.tasks, key: "3")
            destinationButton(.pomodoro, key: "4")
            destinationButton(.analytics, key: "5")

            Divider()

            Button(AppStrings.localized("menu.refreshData")) {
                store?.refreshQuietly()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(store == nil)
        }
    }

    private func destinationButton(
        _ destination: TimeTrackerStore.DesktopDestination,
        key: KeyEquivalent
    ) -> some View {
        Button(destination.title) {
            store?.closeTaskDetailNavigation()
            store?.desktopDestination = destination
        }
        .keyboardShortcut(key, modifiers: [.command])
        .disabled(store == nil)
    }
}
#endif
