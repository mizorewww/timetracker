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
              store.taskDetailNavigationGuard.hasPendingNavigation == false,
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
            navigate {
                store.closeTaskDetailNavigation()
                store.desktopDestination = .today
            }
        case let .openTask(taskID):
            guard store.isTaskDetailRouteValid(taskID) else { return }
            route(url)
        case .open, .openSettings, .startTimerPicker, .newTask:
            route(url)
        }
    }

    private func route(_ url: URL) {
        guard presentationRouter.canPresent else {
            pendingDeepLink.restore(url)
            return
        }
        navigate {
            if store.handleDeepLink(url, presentationRouter: presentationRouter) == .deferred {
                pendingDeepLink.restore(url)
            }
        }
    }

    private func navigate(_ perform: @escaping () -> Void) {
        store.taskDetailNavigationGuard.requestNavigation(
            dismissingActiveDetail: true
        ) {
            perform()
            drain()
        }
    }
}
