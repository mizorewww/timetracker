import SwiftUI

#if os(iOS)
import UIKit

struct iOSRootView: View {
    let store: TimeTrackerStore
    private let layoutPolicy: RootLayoutPolicy

    init(
        store: TimeTrackerStore,
        layoutPolicy: RootLayoutPolicy = RootLayoutPolicy(
            userInterfaceIdiom: UIDevice.current.userInterfaceIdiom
        )
    ) {
        self.store = store
        self.layoutPolicy = layoutPolicy
    }

    var body: some View {
        switch layoutPolicy.shell {
        case .phone:
            PhoneRootView(store: store)
        case .pad:
            iPadRootView(store: store)
        }
    }
}

struct PhoneRootView: View {
    let store: TimeTrackerStore
    @State private var selectedDestination: TimeTrackerStore.DesktopDestination = .today
    @State private var todayPath: [PhoneTodayRoute] = []

    var body: some View {
        TabView(selection: $selectedDestination) {
            Tab(value: .today) {
                NavigationStack(path: $todayPath) {
                    PhoneHomeView(
                        store: store,
                        openSettings: openSettings,
                        openTask: openTask
                    )
                        .navigationDestination(for: PhoneTodayRoute.self) { route in
                            switch route {
                            case .settings:
                                SettingsView(store: store)
                            }
                        }
                }
            } label: {
                Label(AppStrings.today, systemImage: "house")
                    .accessibilityIdentifier("phone.tab.today")
            }

            Tab(value: .inbox) {
                NavigationStack {
                    InboxView(store: store)
                }
            } label: {
                Label(AppStrings.inbox, systemImage: "tray")
                    .accessibilityIdentifier("phone.tab.inbox")
            }

            Tab(value: .tasks) {
                TasksNavigationView(store: store)
            } label: {
                Label(AppStrings.tasks, systemImage: "checklist")
                    .accessibilityIdentifier("phone.tab.tasks")
            }

            Tab(value: .pomodoro) {
                NavigationStack {
                    PomodoroView(store: store)
                }
            } label: {
                Label(AppStrings.focus, systemImage: "timer")
                    .accessibilityIdentifier("phone.tab.focus")
            }

            Tab(value: .analytics) {
                NavigationStack {
                    AnalyticsView(store: store)
                }
            } label: {
                Label(AppStrings.analytics, systemImage: "chart.bar.xaxis")
                    .accessibilityIdentifier("phone.tab.analytics")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .accessibilityIdentifier("phone.tabView")
        .onAppear {
            synchronize(with: store.desktopDestination)
        }
        .onChange(of: store.desktopDestination) { _, destination in
            synchronize(with: destination)
        }
        .onChange(of: selectedDestination) { _, destination in
            let storeDestination = destination == .today && todayPath.last == .settings
                ? TimeTrackerStore.DesktopDestination.settings
                : destination
            guard store.desktopDestination != storeDestination else { return }
            store.desktopDestination = storeDestination
        }
        .onChange(of: todayPath) { _, path in
            guard selectedDestination == .today else { return }
            let destination: TimeTrackerStore.DesktopDestination = path.last == .settings ? .settings : .today
            guard store.desktopDestination != destination else { return }
            store.desktopDestination = destination
        }
    }

    private func openSettings() {
        selectedDestination = .today
        if todayPath.last != .settings {
            todayPath.append(.settings)
        }
        if store.desktopDestination != .settings {
            store.desktopDestination = .settings
        }
    }

    private func openTask(_ taskID: UUID) {
        store.openTaskDetail(taskID)
        selectedDestination = .tasks
    }

    private func synchronize(with destination: TimeTrackerStore.DesktopDestination) {
        switch destination {
        case .settings:
            if selectedDestination != .today {
                selectedDestination = .today
            }
            if todayPath.last != .settings {
                todayPath.append(.settings)
            }
        case .today:
            if selectedDestination != .today {
                selectedDestination = .today
            }
            if !todayPath.isEmpty {
                todayPath.removeAll()
            }
        case .inbox, .tasks, .pomodoro, .analytics:
            if selectedDestination != destination {
                selectedDestination = destination
            }
        }
    }
}

private enum PhoneTodayRoute: Hashable {
    case settings
}

struct iPadRootView: View {
    let store: TimeTrackerStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail
    private let layout = SplitColumnLayoutPolicy.iPad

    var body: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            SidebarView(store: store) {
                preferredCompactColumn = .detail
            }
                .navigationSplitViewColumnWidth(
                    min: layout.sidebar.min,
                    ideal: layout.sidebar.ideal,
                    max: layout.sidebar.max ?? layout.sidebar.ideal
                )
        } detail: {
            DesktopContentView(store: store)
                .navigationSplitViewColumnWidth(min: layout.detail.min, ideal: layout.detail.ideal)
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("ipad.splitNavigation")
        .onChange(of: store.desktopDestination) { _, _ in
            preferredCompactColumn = .detail
        }
    }
}
#endif
