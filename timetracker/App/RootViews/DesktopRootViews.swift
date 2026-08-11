import SwiftUI

/// The detail column's content, shared by both shells.
struct DesktopContentView: View {
    let store: TimeTrackerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            // Sidebar destinations are peers, not forward navigation. A brief
            // crossfade softens the replacement without implying direction.
            ZStack {
                destinationContent
                    .id(store.desktopDestination)
                    .transition(.opacity)
            }
            .animation(
                reduceMotion ? nil : AppMotion.opacity,
                value: store.desktopDestination
            )
        }
        .onChange(of: store.desktopDestination) { _, _ in
            navigationPath = NavigationPath()
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch store.desktopDestination {
        case .today:
            DesktopMainView(store: store)
        case .inbox:
            InboxView(store: store)
        case .tasks:
            TasksNavigationView(
                store: store,
                ownsRegularNavigationStack: false
            )
        case .pomodoro:
            PomodoroView(store: store)
        case .analytics:
            AnalyticsView(store: store)
        case .settings:
            SettingsView(store: store)
        }
    }
}
