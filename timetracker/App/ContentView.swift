import Foundation
import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = TimeTrackerStore()

    var body: some View {
        Group {
            #if os(macOS)
            DesktopRootView(store: store)
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
            Button(AppStrings.localized("common.ok")) {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sheet(item: $store.taskEditorDraft) { draft in
            TaskEditorSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $store.manualTimeDraft) { draft in
            ManualTimeSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $store.segmentEditorDraft) { draft in
            SegmentEditorSheet(store: store, initialDraft: draft)
        }
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
        switch store.preferences.preferredColorScheme {
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
                        if columnVisibility != .all {
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
            isInspectorPresented = inspectorIsRelevant
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
        isInspectorPresented = inspectorIsRelevant
    }
}
#endif

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
