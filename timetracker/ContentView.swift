import Charts
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
private struct NewTaskActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ManualTimeActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct StartTimerActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct StartPomodoroActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct RefreshActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newTaskAction: (() -> Void)? {
        get { self[NewTaskActionKey.self] }
        set { self[NewTaskActionKey.self] = newValue }
    }

    var manualTimeAction: (() -> Void)? {
        get { self[ManualTimeActionKey.self] }
        set { self[ManualTimeActionKey.self] = newValue }
    }

    var startTimerAction: (() -> Void)? {
        get { self[StartTimerActionKey.self] }
        set { self[StartTimerActionKey.self] = newValue }
    }

    var startPomodoroAction: (() -> Void)? {
        get { self[StartPomodoroActionKey.self] }
        set { self[StartPomodoroActionKey.self] = newValue }
    }

    var refreshAction: (() -> Void)? {
        get { self[RefreshActionKey.self] }
        set { self[RefreshActionKey.self] = newValue }
    }
}
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("PreferredColorScheme") private var preferredColorScheme = "system"
    @StateObject private var store = TimeTrackerStore()

    var body: some View {
        Group {
            #if os(macOS)
            ZStack {
                DesktopRootView(store: store)
                    .disabled(store.taskEditorDraft != nil || store.manualTimeDraft != nil || store.segmentEditorDraft != nil)

                DesktopModalLayer(store: store)
            }
            #else
            iOSRootView(store: store)
            #endif
        }
        .task {
            store.configureIfNeeded(context: modelContext)
            store.refreshQuietly()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await store.refreshForForeground()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard scenePhase == .active, AppCloudSync.isEnabled else { continue }
                await MainActor.run {
                    store.refreshQuietly()
                }
            }
        }
        .preferredColorScheme(appColorScheme)
        .alert(Text(.app("error.title")), isPresented: errorBinding) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        #if os(iOS)
        .sheet(item: $store.taskEditorDraft) { draft in
            TaskEditorSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $store.manualTimeDraft) { draft in
            ManualTimeSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $store.segmentEditorDraft) { draft in
            SegmentEditorSheet(store: store, initialDraft: draft)
        }
        #endif
        #if os(macOS)
        .focusedSceneValue(\.newTaskAction) {
            store.presentNewTask()
        }
        .focusedSceneValue(\.manualTimeAction) {
            store.presentManualTime()
        }
        .focusedSceneValue(\.startTimerAction) {
            store.startSelectedTask()
        }
        .focusedSceneValue(\.startPomodoroAction) {
            store.startPomodoroForSelectedTask()
        }
        .focusedSceneValue(\.refreshAction) {
            store.refreshQuietly()
        }
        #endif
    }

    private var errorBinding: Binding<Bool> {
        Binding {
            store.errorMessage != nil
        } set: { newValue in
            if !newValue {
                store.errorMessage = nil
            }
        }
    }

    private var appColorScheme: ColorScheme? {
        switch preferredColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

#if os(iOS)
struct iOSRootView: View {
    @ObservedObject var store: TimeTrackerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            DesktopRootView(store: store)
        } else {
            TabView {
                NavigationStack {
                    PhoneHomeView(store: store)
                }
                .tabItem { Label(AppStrings.localized("tab.home"), systemImage: "house.fill") }

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

                NavigationStack {
                    SettingsView(store: store)
                }
                .tabItem { Label(AppStrings.settings, systemImage: "gearshape") }
            }
        }
    }
}
#endif

struct DesktopRootView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isInspectorPresented = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 270)
                #endif
        } detail: {
            DesktopContentView(store: store)
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 480, ideal: 720)
                #endif
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            togglePrimarySidebar()
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .accessibilityLabel(sidebarToggleTitle)
                    }
                    #endif

                    ToolbarItem(placement: .automatic) {
                        Button {
                            isInspectorPresented.toggle()
                        } label: {
                            Image(systemName: "sidebar.right")
                        }
                        .help(isInspectorPresented ? AppStrings.localized("inspector.hide") : AppStrings.localized("inspector.show"))
                        .disabled(!inspectorIsRelevant)
                    }
                }
                .inspector(isPresented: inspectorBinding) {
                    InspectorView(store: store)
                        .inspectorColumnWidth(min: 240, ideal: 260, max: 320)
                }
        }
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

    private var sidebarToggleTitle: String {
        columnVisibility == .detailOnly
            ? AppStrings.localized("sidebar.show")
            : AppStrings.localized("sidebar.hide")
    }

    private func togglePrimarySidebar() {
        withAnimation(.snappy) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
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
        case .tasks:
            TasksView(store: store)
        case .pomodoro:
            PomodoroView(store: store)
        case .analytics:
            AnalyticsView(store: store)
        case .settings:
            SettingsView(store: store)
        }
    }
}
