import SwiftUI

#if os(iOS)
import UIKit

struct iOSRootView<SyncConflictContent: View>: View {
    let store: TimeTrackerStore
    let syncConflictContent: SyncConflictContent
    private let layoutPolicy: RootLayoutPolicy

    init(
        store: TimeTrackerStore,
        layoutPolicy: RootLayoutPolicy = RootLayoutPolicy(
            userInterfaceIdiom: UIDevice.current.userInterfaceIdiom
        ),
        @ViewBuilder syncConflictContent: () -> SyncConflictContent
    ) {
        self.store = store
        self.layoutPolicy = layoutPolicy
        self.syncConflictContent = syncConflictContent()
    }

    var body: some View {
        switch layoutPolicy.shell {
        case .phone:
            PhoneRootView(
                store: store,
                syncConflictContent: syncConflictContent
            )
        case .pad:
            iPadRootView(store: store)
                .safeAreaInset(edge: .top, spacing: 0) {
                    syncConflictContent
                        .padding(8)
                }
        }
    }
}

struct PhoneRootView<SyncConflictContent: View>: View {
    let store: TimeTrackerStore
    let syncConflictContent: SyncConflictContent
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var selectedDestination: TimeTrackerStore.DesktopDestination = .today
    @State private var todayTaskRoute: TasksRoute?

    var body: some View {
        TabView(selection: $selectedDestination) {
            Tab(value: .today) {
                NavigationStack {
                    PhoneHomeView(
                        store: store,
                        openSettings: openSettings,
                        openTask: openTask
                    )
                    .todayTaskNavigationDestination(
                        store: store,
                        route: $todayTaskRoute
                    )
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
        .safeAreaInset(edge: .top, spacing: 0) {
            syncConflictContent
                .padding(8)
        }
        .accessibilityIdentifier("phone.tabView")
        .onAppear {
            synchronize(with: store.desktopDestination)
        }
        .onChange(of: store.desktopDestination) { _, destination in
            synchronize(with: destination)
        }
        .onChange(of: selectedDestination) { _, destination in
            guard destination != .settings,
                  store.desktopDestination != destination else { return }
            store.desktopDestination = destination
        }
        .onChange(of: presentationRouter.sheet?.id) { _, presentationID in
            guard presentationID == nil,
                  store.desktopDestination == .settings else { return }
            synchronize(with: .settings)
        }
    }

    private func openSettings() {
        guard presentationRouter.presentSettings() else { return }
        restoreContentDestinationAfterPresentingSettings()
    }

    private func openTask(_ taskID: UUID) {
        todayTaskRoute = store.prepareTaskDetailRoute(taskID)
    }

    private func synchronize(with destination: TimeTrackerStore.DesktopDestination) {
        switch destination {
        case .settings:
            openSettings()
        case .today, .inbox, .tasks, .pomodoro, .analytics:
            if selectedDestination != destination {
                selectedDestination = destination
            }
        }
    }

    private func restoreContentDestinationAfterPresentingSettings() {
        guard store.desktopDestination == .settings else { return }
        store.desktopDestination = selectedDestination == .settings ? .today : selectedDestination
    }
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
