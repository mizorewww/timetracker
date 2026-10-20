import SwiftUI

#if os(macOS)
/// Tab bar over a single navigation stack, for a Mac window dragged below
/// `RootLayoutPolicy.regularShellMinimumWidth`. iOS draws the same tabs with
/// UIKit (`TabShellController`, AD-144).
struct CompactShellRootView: View {
    let store: TimeTrackerStore
    let openSettings: () -> Void

    var body: some View {
        TabView(selection: selectedDestinationBinding) {
            ForEach(TimeTrackerStore.DesktopDestination.allCases) { destination in
                Tab(value: destination) {
                    CompactTabPage(store: store, destination: destination, openSettings: openSettings)
                } label: {
                    Label(destination.title, systemImage: destination.visual.symbolName)
                }
            }
        }
        // Kept verbatim: this is the identifier the existing XCUITests select on.
        .accessibilityIdentifier("phone.tabView")
    }

    private var selectedDestinationBinding: Binding<TimeTrackerStore.DesktopDestination> {
        Binding(
            get: { store.desktopDestination },
            set: { store.desktopDestination = $0 }
        )
    }
}
#endif

/// One destination's page in the compact shell, in its own navigation stack.
struct CompactTabPage: View {
    let store: TimeTrackerStore
    let destination: TimeTrackerStore.DesktopDestination
    let openSettings: () -> Void

    var body: some View {
        switch destination {
        case .today:
            NavigationStack {
                CompactHomeView(store: store, openSettings: openSettings, openTask: store.openTodayTaskDetail)
                    .todayTaskNavigationDestination(store: store, route: todayTaskRoute)
            }
            .environment(\.pageLiveClocksActive, store.desktopDestination == .today)
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
            .environment(\.pageLiveClocksActive, store.desktopDestination == .pomodoro)
        case .analytics:
            NavigationStack {
                AnalyticsView(store: store)
            }
        }
    }

    private var todayTaskRoute: Binding<TasksRoute?> {
        Binding(
            get: { store.todayTaskRoute },
            set: { store.todayTaskRoute = $0 }
        )
    }
}
