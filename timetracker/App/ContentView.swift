import SwiftData
import SwiftUI

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
            #if os(iOS) && canImport(WatchConnectivity)
            WatchConnectivityBridge.shared.commandHandler = { command in
                store.handleWatchCommand(command)
            }
            WatchConnectivityBridge.shared.activateIfSupported()
            #endif
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
        .onOpenURL { url in
            store.handleDeepLink(url)
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
        .sheet(item: $store.taskCategoryEditorDraft) { draft in
            TaskCategoryEditorSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $store.manualTimeDraft) { draft in
            ManualTimeSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $store.segmentEditorDraft) { draft in
            SegmentEditorSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $store.inboxSuggestionEditorDraft) { draft in
            InboxSuggestionEditorSheet(store: store, initialDraft: draft)
        }
        #if os(iOS)
        .sheet(isPresented: $store.isStartTaskPickerPresented) {
            NavigationStack {
                TaskStartPicker(store: store) {
                    store.isStartTaskPickerPresented = false
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.regularMaterial)
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
        switch store.preferences.preferredColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
