import Foundation

@MainActor
struct AppSceneDeepLinkCoordinator {
    let store: TimeTrackerStore
    let presentationRouter: AppPresentationRouter
    let pendingDeepLinks: PendingDeepLinkQueue

    func enqueueAndDrain(_ url: URL) {
        guard pendingDeepLinks.enqueue(url) else { return }
        drain()
    }

    func drain() {
        guard pendingDeepLinks.urls.isEmpty == false,
              store.taskDetailNavigationGuard.hasPendingNavigation == false else {
            return
        }

        let queuedURLs = pendingDeepLinks.drain()
        var preparedActions = prepareActions(for: queuedURLs)
        if presentationRouter.canPresent == false {
            let deferredURLs = preparedActions.compactMap(\.deepLinkURL)
            pendingDeepLinks.restoreToFront(deferredURLs)
            preparedActions.removeAll { $0.deepLinkURL != nil }
        }
        guard preparedActions.isEmpty == false else { return }

        store.taskDetailNavigationGuard.requestNavigation(
            dismissingActiveDetail: true
        ) {
            perform(preparedActions)
            drain()
        }
    }

    private func prepareActions(for urls: [URL]) -> [PreparedDeepLinkAction] {
        let router = AppDeepLinkRouter()
        return urls.compactMap { url in
            guard let action = router.action(for: url) else { return nil }
            switch action {
            case .startTimer, .stopTimer:
                let disposition = store.handleDeepLink(
                    url,
                    presentationRouter: presentationRouter,
                    routesAfterSystemAction: false
                )
                return disposition == .handled ? .routeToToday : nil
            case .openTask(let taskID):
                guard store.isTaskDetailRouteValid(taskID) else {
                    return nil
                }
                return .deepLink(url)
            case .open, .startTimerPicker, .newTask:
                return .deepLink(url)
            }
        }
    }

    private func perform(_ actions: [PreparedDeepLinkAction]) {
        for action in actions {
            switch action {
            case .routeToToday:
                store.closeTaskDetailNavigation()
                store.desktopDestination = .today
            case .deepLink(let url):
                let disposition = store.handleDeepLink(
                    url,
                    presentationRouter: presentationRouter
                )
                if disposition == .deferred {
                    pendingDeepLinks.enqueue(url)
                }
            }
        }
    }
}

private enum PreparedDeepLinkAction {
    case deepLink(URL)
    case routeToToday

    var deepLinkURL: URL? {
        guard case .deepLink(let url) = self else { return nil }
        return url
    }
}
