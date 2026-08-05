import SwiftUI

/// Tab bar over a single navigation stack, for widths too narrow for a split
/// view. Used by iPhone, by an iPad in Split View or Slide Over, and by a Mac
/// window dragged below `RootLayoutPolicy.regularShellMinimumWidth`.
struct CompactShellRootView<SyncConflictContent: View>: View {
    let store: TimeTrackerStore
    let syncConflictContent: SyncConflictContent
    let requestOpenSettings: () -> Bool
    @State private var isTabDiscardConfirmationPresented = false
    @State private var tabNavigationConfirmationRequestID: UUID?

    var body: some View {
        TabView(selection: selectedDestinationBinding) {
            Tab(value: .today) {
                NavigationStack {
                    CompactHomeView(
                        store: store,
                        openSettings: openSettings,
                        openTask: openTask
                    )
                    .todayTaskNavigationDestination(
                        store: store,
                        route: todayTaskRoute
                    )
                }
                .environment(
                    \.pageLiveClocksActive,
                    store.desktopDestination == .today
                )
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
                .environment(
                    \.pageLiveClocksActive,
                    store.desktopDestination == .pomodoro
                )
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
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .compactTabNavigationSafety(
            isPresented: $isTabDiscardConfirmationPresented,
            requestID: $tabNavigationConfirmationRequestID,
            navigationGuard: store.taskDetailNavigationGuard
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            syncConflictContent
                .padding(8)
        }
        // Kept verbatim: this is the identifier the existing XCUITests select on.
        .accessibilityIdentifier("phone.tabView")
    }

    private var selectedDestinationBinding: Binding<TimeTrackerStore.DesktopDestination> {
        Binding(
            get: { store.desktopDestination },
            set: { destination in
                guard destination != .settings,
                      destination != store.desktopDestination else { return }
                let requestID = store.taskDetailNavigationGuard.requestNavigation(
                    presentingConfirmationInSource: false,
                    dismissPresentedConfirmation: dismissTabNavigationConfirmation
                ) {
                    store.desktopDestination = destination
                }
                if let requestID {
                    tabNavigationConfirmationRequestID = requestID
                    isTabDiscardConfirmationPresented = true
                }
            }
        )
    }

    private func dismissTabNavigationConfirmation(requestID: UUID) {
        guard tabNavigationConfirmationRequestID == requestID else { return }
        tabNavigationConfirmationRequestID = nil
        isTabDiscardConfirmationPresented = false
    }

    private func openSettings() {
        _ = requestOpenSettings()
    }

    private func openTask(_ taskID: UUID) {
        store.openTodayTaskDetail(taskID)
    }

    private var todayTaskRoute: Binding<TasksRoute?> {
        Binding(
            get: { store.todayTaskRoute },
            set: { store.todayTaskRoute = $0 }
        )
    }
}
