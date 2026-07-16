import SwiftUI

struct DesktopRootView: View {
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    let store: TimeTrackerStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    #if os(macOS)
    @State private var lastContentDestination: TimeTrackerStore.DesktopDestination = .today
    #endif
    private let layout = SplitColumnLayoutPolicy.mac

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("mac.splitNavigation")
        #if os(macOS)
        .focusedSceneValue(\.timeTrackerStore, store)
        .onAppear {
            routeSettingsDestination(store.desktopDestination)
        }
        .onChange(of: store.desktopDestination) { _, destination in
            routeSettingsDestination(destination)
        }
        #endif
    }

    private var sidebarColumn: some View {
        SidebarView(store: store)
            #if os(macOS)
            .navigationSplitViewColumnWidth(
                min: layout.sidebar.min,
                ideal: layout.sidebar.ideal,
                max: layout.sidebar.max ?? layout.sidebar.ideal
            )
            #endif
    }

    private var detailColumn: some View {
        DesktopContentView(store: store)
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: layout.detail.min, ideal: layout.detail.ideal)
            #endif
    }

    #if os(macOS)
    private func routeSettingsDestination(_ destination: TimeTrackerStore.DesktopDestination) {
        guard destination == .settings else {
            lastContentDestination = destination
            return
        }

        openSettings()
        store.desktopDestination = lastContentDestination
    }
    #endif
}

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
