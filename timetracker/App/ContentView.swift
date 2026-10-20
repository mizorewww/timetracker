import Foundation
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: TimeTrackerStore
    @State private var presentationRouter: AppPresentationRouter
    @State private var feedbackRouter: AppSceneFeedbackRouter
    @State private var pendingDeepLink = PendingDeepLink()
    @State private var hasFinishedInitialConfiguration = false
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    #if os(iOS) && canImport(WatchConnectivity)
    @State private var watchCommandRegistrationID: UUID?
    #endif

    init() {
        self.init(store: TimeTrackerStore())
    }

    init(store: TimeTrackerStore) {
        _store = State(initialValue: store)
        let feedbackRouter = AppSceneFeedbackRouter()
        _feedbackRouter = State(initialValue: feedbackRouter)
        _presentationRouter = State(
            initialValue: AppPresentationRouter(feedbackRouter: feedbackRouter)
        )
    }

    var body: some View {
        Group {
            if store.effectivePersistenceWriteSafety == .ready {
                #if os(iOS)
                UIKitShellView(store: store)
                    .ignoresSafeArea()
                #else
                AppRootView(store: store)
                #endif
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
        #if os(macOS)
        .onAppear {
            presentationRouter.openNativeSettings = { openSettings() }
        }
        #endif
        .task {
            do {
                try store.configureIfNeeded(context: modelContext)
            } catch {
                feedbackRouter.present(error)
            }
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
            store.materializeCurrentDailyTaskRecurrences()
        }
        .taskRecurrenceLifecycle(store: store, isConfigured: hasFinishedInitialConfiguration)
        .onOpenURL { url in
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
        .onChange(of: presentationRouter.sheet?.id) { _, presentationID in
            guard presentationID == nil else { return }
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
}
