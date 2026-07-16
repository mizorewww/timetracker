import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: TimeTrackerStore
    @State private var presentationRouter = AppPresentationRouter()
    @State private var feedbackRouter = AppSceneFeedbackRouter()
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
        .environment(presentationRouter)
        .environment(feedbackRouter)
        .appPresentationHost(
            store: store,
            router: presentationRouter,
            feedbackRouter: feedbackRouter
        )
        .appSceneFeedbackHost(router: feedbackRouter)
        #if os(iOS)
        .overlay(alignment: .bottom) {
            syncConflictNotice
                .padding(.horizontal, 12)
                .padding(.bottom, 84)
        }
        #else
        .safeAreaInset(edge: .top, spacing: 0) {
            syncConflictNotice
                .padding(8)
        }
        #endif
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
            routeOrQueueDeepLink(url)
        }
        .onDisappear {
            pendingDeepLinks.removeAll()
            hasFinishedInitialConfiguration = false
            unregisterFromWatchCommands()
        }
        .onChange(of: store.errorMessage) { _, message in
            relayStoreError(message)
        }
        .onChange(of: store.pendingSyncConflict?.id) { _, _ in
            dismissedSyncConflictID = nil
        }
        .onChange(of: presentationRouter.sheet?.id) { _, presentationID in
            guard presentationID == nil else { return }
            drainPendingDeepLinks()
        }
    }

    private func drainPendingDeepLinks() {
        guard AppCloudSync.allowsUserWrites, store.taskRepository != nil else { return }
        for url in pendingDeepLinks.drain() {
            routeOrQueueDeepLink(url)
        }
    }

    private func routeOrQueueDeepLink(_ url: URL) {
        let disposition = store.handleDeepLink(
            url,
            presentationRouter: presentationRouter
        )
        if disposition == .deferred {
            pendingDeepLinks.enqueue(url)
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

    private func relayStoreError(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        feedbackRouter.present(
            title: AppStrings.localized("error.title"),
            message: message
        )
        if store.errorMessage == message {
            store.errorMessage = nil
        }
    }

    @ViewBuilder
    private var syncConflictNotice: some View {
        if let conflict = store.pendingSyncConflict,
           dismissedSyncConflictID != conflict.id {
            SyncConflictNotice(
                onReview: {
                    dismissedSyncConflictID = conflict.id
                    store.desktopDestination = .settings
                },
                onDismiss: {
                    dismissedSyncConflictID = conflict.id
                }
            )
        }
    }

}
