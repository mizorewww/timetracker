import Foundation
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: TimeTrackerStore
    @State private var presentationRouter = AppPresentationRouter()
    @State private var feedbackRouter = AppSceneFeedbackRouter()
    @State private var pendingDeepLink = PendingDeepLink()
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
            if store.effectivePersistenceWriteSafety == .ready {
                AppRootView(store: store)
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
        .task {
            store.configureIfNeeded(context: modelContext)
            guard store.persistenceWriteSafety == .ready else { return }
            hasFinishedInitialConfiguration = true
            drainPendingDeepLinks()
            registerForWatchCommandsIfNeeded()
            store.materializeCurrentDailyTaskRecurrences()
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
            }
        }
        .taskRecurrenceLifecycle(store: store, isConfigured: hasFinishedInitialConfiguration)
        .onOpenURL { url in
            guard AppDeepLinkRouter().action(for: url) != nil else { return }
            guard AppCloudSync.allowsUserWrites, store.taskRepository != nil else {
                pendingDeepLink.set(url)
                return
            }
            deepLinkCoordinator.enqueueAndDrain(url)
        }
        .onDisappear {
            pendingDeepLink.clear()
            hasFinishedInitialConfiguration = false
            unregisterFromWatchCommands()
        }
        .onChange(of: store.errorMessage) { _, message in
            relayStoreError(message)
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
            pendingDeepLink: pendingDeepLink
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
}
