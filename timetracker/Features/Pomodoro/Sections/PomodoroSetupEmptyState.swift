import SwiftUI

struct PomodoroSetupEmptyState: View {
    let store: TimeTrackerStore

    var body: some View {
        ContentUnavailableView {
            Label(AppStrings.localized("pomodoro.noTasks.title"), systemImage: "timer")
        } description: {
            Text(.app("pomodoro.noTasks.description"))
        } actions: {
            Button(AppStrings.newTask) {
                store.presentNewTask(preservingDestination: .pomodoro)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("pomodoro.emptyState.newTask")
        }
        .accessibilityIdentifier("pomodoro.emptyState")
    }
}
