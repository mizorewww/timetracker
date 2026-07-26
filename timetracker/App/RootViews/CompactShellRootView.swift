import SwiftUI

/// Tab bar over a single navigation stack, for widths too narrow for a split
/// view. Used by iPhone, by an iPad in Split View or Slide Over, and by a Mac
/// window dragged below `RootLayoutPolicy.regularShellMinimumWidth`.
struct CompactShellRootView<SyncConflictContent: View>: View {
    let store: TimeTrackerStore
    let syncConflictContent: SyncConflictContent
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var selectedDestination: TimeTrackerStore.DesktopDestination = .today
    @State private var todayTaskRoute: TasksRoute?
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
        .onAppear {
            synchronize(with: store.desktopDestination)
        }
        .onChange(of: store.desktopDestination) { _, destination in
            synchronize(with: destination)
        }
        .onChange(of: presentationRouter.sheet?.id) { _, presentationID in
            guard presentationID == nil,
                  store.desktopDestination == .settings else { return }
            synchronize(with: .settings)
        }
    }

    private var selectedDestinationBinding: Binding<TimeTrackerStore.DesktopDestination> {
        Binding(
            get: { selectedDestination },
            set: { destination in
                guard destination != .settings,
                      destination != selectedDestination else { return }
                let requestID = store.taskDetailNavigationGuard.requestNavigation(
                    presentingConfirmationInSource: false,
                    dismissPresentedConfirmation: dismissTabNavigationConfirmation
                ) {
                    selectedDestination = destination
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
