import SwiftUI

struct DesktopRootView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var isInspectorPresented = false
    private let layout = SplitColumnLayoutPolicy.mac

    var body: some View {
        NavigationSplitView {
            sidebarColumn
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            isInspectorPresented = inspectorIsRelevant
        }
        .onChange(of: store.desktopDestination) { _, _ in
            updateInspectorVisibility()
        }
        .onChange(of: store.selectedTaskID) { _, _ in
            updateInspectorVisibility()
        }
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
            .toolbar {
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
        if inspectorIsRelevant {
            isInspectorPresented = true
        } else {
            isInspectorPresented = false
        }
    }
}

struct DesktopContentView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        switch store.desktopDestination {
        case .today:
            DesktopMainView(store: store)
        case .inbox:
            InboxView(store: store)
        case .tasks:
            if let taskID = store.desktopTaskDetailID, store.task(for: taskID) != nil {
                NavigationStack {
                    TaskDetailView(store: store, taskID: taskID)
                }
            } else {
                NavigationStack {
                    TasksView(store: store)
                }
            }
        case .pomodoro:
            PomodoroView(store: store)
        case .analytics:
            AnalyticsView(store: store)
        case .settings:
            SettingsView(store: store)
        }
    }
}
