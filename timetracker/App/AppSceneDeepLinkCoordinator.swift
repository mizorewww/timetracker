import Foundation

@MainActor
struct AppSceneDeepLinkCoordinator {
    let store: TimeTrackerStore
    let presentationRouter: AppPresentationRouter
    let pendingDeepLink: PendingDeepLink

    func enqueueAndDrain(_ url: URL) {
        guard pendingDeepLink.set(url) else { return }
        drain()
    }

    /// Runs the pending link; one that must wait for an open sheet stays
    /// pending unless a newer link arrived meanwhile.
    func drain() {
        guard let url = pendingDeepLink.take() else { return }
        if store.handleDeepLink(url, presentationRouter: presentationRouter) == .deferred {
            pendingDeepLink.restore(url)
        }
    }
}
