import SwiftUI

/// The detail column's content, shared by both shells.
struct DesktopContentView: View {
    let store: TimeTrackerStore

    var body: some View {
        switch store.desktopDestination {
        case .today:
            NavigationStack {
                DesktopMainView(store: store)
            }
        case .inbox:
            NavigationStack {
                InboxView(store: store)
            }
        case .tasks:
            TasksNavigationView(store: store)
        case .pomodoro:
            NavigationStack {
                PomodoroView(store: store)
            }
        case .analytics:
            NavigationStack {
                AnalyticsView(store: store)
            }
        case .settings:
            NavigationStack {
                SettingsView(store: store)
            }
        }
    }
}
