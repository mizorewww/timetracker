import Foundation
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
    @State private var preheatPhase = -1
    #if os(iOS) && canImport(WatchConnectivity)
    @State private var watchCommandRegistrationID: UUID?
    #endif

    private func advancePreheat() {
        Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(for: .seconds(0.4))
            guard preheatPhase >= 0 else { return }
            if preheatPhase < ViewTypePreheater.phaseCount - 1 {
                preheatPhase += 1
            } else {
                preheatPhase = -1
            }
        }
    }

    init() {
        _store = State(initialValue: TimeTrackerStore())
    }

    init(store: TimeTrackerStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        Group {
            if store.effectivePersistenceWriteSafety == .ready {
                AppRootView(store: store) {
                    syncConflictNotice
                }
            } else {
                PersistenceRecoveryView(safety: store.effectivePersistenceWriteSafety)
            }
        }
        .accessibilityIdentifier(hasFinishedInitialConfiguration ? "app.initialConfiguration.ready" : "app.initialConfiguration.pending")
        .environment(presentationRouter)
        .environment(feedbackRouter)
        .appPresentationHost(
            store: store,
            router: presentationRouter,
            feedbackRouter: feedbackRouter
        )
        .appSceneFeedbackHost(router: feedbackRouter)
        .overlay {
            if preheatPhase >= 0 {
                ViewTypePreheater.preheaterView(
                    phase: preheatPhase,
                    store: store
                )
                .environment(presentationRouter)
                .environment(feedbackRouter)
                .environment(\.layoutShell, .compact)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear {
                    advancePreheat()
                }
            }
        }
        // The sync-conflict banner is installed by whichever shell `AppRootView`
        // picks, so it no longer needs a second macOS-only insertion here.
        .task {
            store.configureIfNeeded(context: modelContext)
            guard store.persistenceWriteSafety == .ready else { return }
            hasFinishedInitialConfiguration = true
            drainPendingDeepLinks()
            registerForWatchCommandsIfNeeded()
            store.materializeCurrentDailyTaskRecurrences()
            // Resolve the tab pages' Swift view types off-screen right after
            // launch, so first switches do not pay the lazy metadata-
            // resolution cost (~500 ms for Tasks on dense data).
            if preheatPhase < 0 {
                preheatPhase = 0
            }
            await store.refreshAppleHealthTimelineIfEnabled()
            #if DEBUG
            if await CloudSyncSmokeTestRunner.runIfRequested(context: modelContext, store: store) {
                return
            }
            #endif
            #if DEBUG
            store.applyLiveLLMConfigurationIfRequested()
            store.applyChecklistVisualSuggestionFixtureIfRequested()
            store.applyFirstHealthTimelineFixtureIfRequested()
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
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            guard hasFinishedInitialConfiguration, scenePhase == .active else { return }
            Task { @MainActor in
                await store.refreshAppleHealthTimelineIfEnabled()
            }
        }
        .onChange(of: store.persistenceWriteSafety) { _, safety in
            guard safety == .ready else {
                hasFinishedInitialConfiguration = false
                unregisterFromWatchCommands()
                return
            }
            guard hasFinishedInitialConfiguration == false else { return }
            hasFinishedInitialConfiguration = true
            drainPendingDeepLinks()
            registerForWatchCommandsIfNeeded()
            Task { @MainActor in
                store.materializeCurrentDailyTaskRecurrences()
                await store.refreshAppleHealthTimelineIfEnabled()
            }
        }
        .taskRecurrenceLifecycle(store: store, isConfigured: hasFinishedInitialConfiguration)
        .onOpenURL { url in
            guard AppDeepLinkRouter().action(for: url) != nil else { return }
            guard AppCloudSync.allowsUserWrites, store.taskRepository != nil else {
                pendingDeepLinks.enqueue(url)
                return
            }
            deepLinkCoordinator.enqueueAndDrain(url)
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
        .onChange(of: store.taskDetailNavigationGuard.hasPendingNavigation) { _, hasPendingNavigation in
            guard hasPendingNavigation == false else { return }
            drainPendingDeepLinks()
        }
    }

    private func drainPendingDeepLinks() {
        guard AppCloudSync.allowsUserWrites, store.taskRepository != nil else { return }
        deepLinkCoordinator.drain()
    }

    private var deepLinkCoordinator: AppSceneDeepLinkCoordinator {
        AppSceneDeepLinkCoordinator(
            store: store,
            presentationRouter: presentationRouter,
            pendingDeepLinks: pendingDeepLinks
        )
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
        if store.effectivePersistenceWriteSafety == .ready,
           let conflict = store.pendingSyncConflict,
           dismissedSyncConflictID != conflict.id
        {
            SyncConflictNotice(
                onReview: {
                    store.taskDetailNavigationGuard.requestNavigation(
                        dismissingActiveDetail: true
                    ) {
                        dismissedSyncConflictID = conflict.id
                        store.closeTaskDetailNavigation()
                        store.desktopDestination = .settings
                    }
                },
                onDismiss: {
                    dismissedSyncConflictID = conflict.id
                }
            )
        }
    }
}
