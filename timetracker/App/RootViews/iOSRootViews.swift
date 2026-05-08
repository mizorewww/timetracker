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

    var body: some View {
        TabView {
            NavigationStack {
                PhoneHomeView(store: store)
            }
            .tabItem { Label(AppStrings.localized("tab.home"), systemImage: "house.fill") }

            NavigationStack {
                InboxView(store: store)
            }
            .tabItem { Label(AppStrings.inbox, systemImage: "tray") }

            NavigationStack {
                TasksView(store: store)
            }
            .tabItem { Label(AppStrings.tasks, systemImage: "list.bullet") }

            NavigationStack {
                PomodoroView(store: store)
            }
            .tabItem { Label(AppStrings.pomodoro, systemImage: "timer") }

            NavigationStack {
                AnalyticsView(store: store)
            }
            .tabItem { Label(AppStrings.analytics, systemImage: "chart.bar.xaxis") }
        }
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
                            Button {
                                columnVisibility = .all
                            } label: {
                                Label(AppStrings.localized("sidebar.show"), systemImage: "sidebar.left")
                                    .labelStyle(.iconOnly)
                            }
                            .accessibilityLabel(AppStrings.localized("sidebar.show"))
                        }
                    }

                    ToolbarItem(placement: .automatic) {
                        Button {
                            isInspectorPresented.toggle()
                        } label: {
                            Image(systemName: "sidebar.right")
                        }
                        .disabled(!inspectorIsRelevant)
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
