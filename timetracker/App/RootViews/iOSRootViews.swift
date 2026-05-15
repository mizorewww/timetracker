import SwiftUI

#if os(iOS)
struct iOSRootView: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            iPadRootView(store: store)
        } else {
            PhoneRootView(store: store)
        }
    }
}

struct PhoneRootView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var selectedDestination: TimeTrackerStore.DesktopDestination = .today

    var body: some View {
        TabView(selection: $selectedDestination) {
            NavigationStack {
                PhoneHomeView(store: store)
            }
            .tabItem { Label(AppStrings.localized("tab.home"), systemImage: "house.fill") }
            .tag(TimeTrackerStore.DesktopDestination.today)

            NavigationStack {
                InboxView(store: store)
            }
            .tabItem { Label(AppStrings.inbox, systemImage: "tray") }
            .tag(TimeTrackerStore.DesktopDestination.inbox)

            NavigationStack {
                TasksView(store: store)
            }
            .tabItem { Label(AppStrings.tasks, systemImage: "list.bullet") }
            .tag(TimeTrackerStore.DesktopDestination.tasks)

            NavigationStack {
                PomodoroView(store: store)
            }
            .tabItem { Label(AppStrings.pomodoro, systemImage: "timer") }
            .tag(TimeTrackerStore.DesktopDestination.pomodoro)

            NavigationStack {
                AnalyticsView(store: store)
            }
            .tabItem { Label(AppStrings.analytics, systemImage: "chart.bar.xaxis") }
            .tag(TimeTrackerStore.DesktopDestination.analytics)
        }
        .onAppear {
            selectedDestination = phoneDestination(for: store.desktopDestination)
        }
        .onChange(of: store.desktopDestination) { _, destination in
            let phoneDestination = phoneDestination(for: destination)
            guard selectedDestination != phoneDestination else { return }
            selectedDestination = phoneDestination
        }
        .onChange(of: selectedDestination) { _, destination in
            guard store.desktopDestination != destination else { return }
            store.desktopDestination = destination
        }
    }

    private func phoneDestination(for destination: TimeTrackerStore.DesktopDestination) -> TimeTrackerStore.DesktopDestination {
        destination == .settings ? .today : destination
    }
}

struct iPadRootView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isInspectorPresented = false
    private let layout = SplitColumnLayoutPolicy.iPad

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(
                    min: layout.sidebar.min,
                    ideal: layout.sidebar.ideal,
                    max: layout.sidebar.max ?? layout.sidebar.ideal
                )
        } detail: {
            DesktopContentView(store: store)
                .navigationSplitViewColumnWidth(min: layout.detail.min, ideal: layout.detail.ideal)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if columnVisibility == .detailOnly {
                            SidebarRevealButton {
                                columnVisibility = .all
                            }
                        }
                    }

                    ToolbarItem(placement: .automatic) {
                        InspectorToggleButton(
                            isPresented: isInspectorPresented,
                            isEnabled: inspectorIsRelevant
                        ) {
                            isInspectorPresented.toggle()
                        }
                    }
                }
                .inspector(isPresented: inspectorBinding) {
                    InspectorView(store: store)
                        .inspectorColumnWidth(
                            min: layout.inspector.min,
                            ideal: layout.inspector.ideal,
                            max: layout.inspector.max ?? layout.inspector.ideal
                        )
                }
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("ipad.splitNavigation")
        .onAppear {
            if !inspectorIsRelevant {
                isInspectorPresented = false
            }
        }
        .onChange(of: store.desktopDestination) { _, _ in
            updateInspectorVisibility()
        }
        .onChange(of: store.selectedTaskID) { _, _ in
            updateInspectorVisibility()
        }
    }

    private var inspectorIsRelevant: Bool {
        store.desktopDestination == .today && store.selectedTask != nil
    }

    private var inspectorBinding: Binding<Bool> {
        Binding {
            isInspectorPresented && inspectorIsRelevant
        } set: { newValue in
            isInspectorPresented = newValue
        }
    }

    private func updateInspectorVisibility() {
        if !inspectorIsRelevant {
            isInspectorPresented = false
        }
    }
}
#endif
