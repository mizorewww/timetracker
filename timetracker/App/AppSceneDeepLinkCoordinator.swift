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

    func drain() {
        guard pendingDeepLink.url != nil,
              let url = pendingDeepLink.take(),
              let action = AppDeepLinkRouter().action(for: url)
        else {
            return
        }

        switch action {
        case .startTimer, .stopTimer:
            // System actions run now; only the navigation waits for the guard.
            let disposition = store.handleDeepLink(
                url,
                presentationRouter: presentationRouter,
                routesAfterSystemAction: false
            )
            guard disposition == .handled else { return }
            store.closeTaskDetailNavigation()
            store.desktopDestination = .today
            drain()
        case let .openTask(taskID):
            guard store.isTaskDetailRouteValid(taskID) else { return }
            route(url)
        case .open, .openSettings, .startTimerPicker, .newTask:
            route(url)
        }
    }

    private func route(_ url: URL) {
        if store.handleDeepLink(url, presentationRouter: presentationRouter) == .deferred {
            pendingDeepLink.restore(url)
            return
        }
        drain()
    }
}
