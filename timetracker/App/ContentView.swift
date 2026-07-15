import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: TimeTrackerStore
    @State private var dismissedSyncConflictID: UUID?
    @State private var pendingDeepLinks = PendingDeepLinkQueue()
    @State private var hasFinishedInitialConfiguration = false
    #if os(iOS) && canImport(WatchConnectivity)
    @State private var watchCommandRegistrationID: UUID?
    #endif

    init() {
        _store = State(initialValue: TimeTrackerStore())
    }

    init(store: TimeTrackerStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        @Bindable var bindableStore = store
        Group {
            if AppCloudSync.allowsUserWrites {
                #if os(macOS)
                DesktopRootView(store: store)
                #else
                iOSRootView(store: store)
                #endif
            } else {
                PersistenceRecoveryView(safety: AppCloudSync.persistenceWriteSafety)
            }
        }
        .task {
            guard AppCloudSync.allowsUserWrites else { return }
            store.configureIfNeeded(context: modelContext)
            hasFinishedInitialConfiguration = true
            drainPendingDeepLinks()
            registerForWatchCommandsIfNeeded()
            #if DEBUG
            if await CloudSyncSmokeTestRunner.runIfRequested(context: modelContext, store: store) {
                return
            }
            #endif
            #if DEBUG
            store.applyUIAuditRouteIfRequested()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            updateWatchCommandRoute(for: phase)
            guard phase == .active,
                  hasFinishedInitialConfiguration,
                  AppCloudSync.allowsUserWrites else { return }
            Task { @MainActor in
                await store.refreshForForeground()
            }
        }
        .onOpenURL { url in
            guard AppDeepLinkRouter().action(for: url) != nil else { return }
            guard AppCloudSync.allowsUserWrites, store.taskRepository != nil else {
                pendingDeepLinks.enqueue(url)
                return
            }
            store.handleDeepLink(url)
        }
        .onDisappear {
            pendingDeepLinks.removeAll()
            hasFinishedInitialConfiguration = false
            unregisterFromWatchCommands()
        }
        .alert(Text(.app("error.title")), isPresented: errorBinding) {
            Button(AppStrings.localized("common.ok")) {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .confirmationDialog(
            AppStrings.localized("dialog.syncConflict.title"),
            isPresented: syncConflictDialogBinding,
            titleVisibility: .visible
        ) {
            Button(AppStrings.localized("dialog.syncConflict.uploadLocal"), role: .destructive) {
                store.resolveSyncConflict(.uploadLocal)
            }
            Button(AppStrings.localized("dialog.syncConflict.downloadCloud"), role: .destructive) {
                store.resolveSyncConflict(.downloadCloud)
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(syncConflictMessage)
        }
        .onChange(of: store.pendingSyncConflict?.id) { _, _ in
            dismissedSyncConflictID = nil
        }
        .sheet(item: $bindableStore.taskEditorDraft) { draft in
            TaskEditorSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $bindableStore.taskCategoryEditorDraft) { draft in
            TaskCategoryEditorSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $bindableStore.manualTimeDraft) { draft in
            ManualTimeSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $bindableStore.segmentEditorDraft) { draft in
            SegmentEditorSheet(store: store, initialDraft: draft)
        }
        .sheet(item: $bindableStore.inboxSuggestionEditorDraft) { draft in
            InboxSuggestionEditorSheet(store: store, initialDraft: draft)
        }
        .sheet(isPresented: $bindableStore.isStartTaskPickerPresented) {
            NavigationStack {
                TaskStartPicker(store: store) {
                    store.isStartTaskPickerPresented = false
                }
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #else
            .frame(minWidth: 420, minHeight: 520)
            #endif
        }
    }

    private func drainPendingDeepLinks() {
        guard AppCloudSync.allowsUserWrites, store.taskRepository != nil else { return }
        for url in pendingDeepLinks.drain() {
            store.handleDeepLink(url)
        }
    }

    private func registerForWatchCommandsIfNeeded() {
        #if os(iOS) && canImport(WatchConnectivity)
        guard watchCommandRegistrationID == nil else { return }
        watchCommandRegistrationID = WatchCommandRouter.shared.register(
            store: store,
            isActive: scenePhase == .active
        )
        #endif
    }

    private func updateWatchCommandRoute(for phase: ScenePhase) {
        #if os(iOS) && canImport(WatchConnectivity)
        guard let watchCommandRegistrationID else { return }
        WatchCommandRouter.shared.update(
            registrationID: watchCommandRegistrationID,
            isActive: phase == .active
        )
        #endif
    }

    private func unregisterFromWatchCommands() {
        #if os(iOS) && canImport(WatchConnectivity)
        guard let watchCommandRegistrationID else { return }
        WatchCommandRouter.shared.unregister(registrationID: watchCommandRegistrationID)
        self.watchCommandRegistrationID = nil
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

    private var syncConflictDialogBinding: Binding<Bool> {
        Binding {
            guard let conflict = store.pendingSyncConflict else { return false }
            return dismissedSyncConflictID != conflict.id
        } set: { isPresented in
            if !isPresented {
                dismissedSyncConflictID = store.pendingSyncConflict?.id
            }
        }
    }

    private var syncConflictMessage: String {
        guard let conflict = store.pendingSyncConflict else { return "" }
        return String(
            format: AppStrings.localized("dialog.syncConflict.message"),
            conflict.localSummary,
            conflict.cloudSummary
        )
    }

}
