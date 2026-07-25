import Foundation

enum AppDeepLinkHandlingDisposition: Equatable {
    case handled
    case deferred
    case rejected
}

extension TimeTrackerStore {
    func handleDeepLink(
        _ url: URL,
        presentationRouter: AppPresentationRouter,
        routesAfterSystemAction: Bool = true
    ) -> AppDeepLinkHandlingDisposition {
        let router = AppDeepLinkRouter()
        guard let action = router.action(for: url) else { return .rejected }

        if presentationRouter.canPresent == false {
            switch action {
            case .startTimer, .stopTimer:
                break
            case .open, .startTimerPicker, .newTask, .openTask:
                return .deferred
            }
        }

        switch action {
        case let .open(destination):
            closeTaskDetailNavigation()
            desktopDestination = destination
            return .handled
        case .startTimerPicker:
            guard presentationRouter.presentStartTaskPicker() else { return .deferred }
            closeTaskDetailNavigation()
            desktopDestination = .today
            return .handled
        case let .startTimer(taskID, source):
            guard startTask(taskID: taskID, source: source) else {
                return .rejected
            }
            if routesAfterSystemAction {
                closeTaskDetailNavigation()
                desktopDestination = .today
            }
            return .handled
        case let .stopTimer(target):
            let didStop: Bool = switch target {
            case let .some(.segment(segmentID)):
                stopTimer(segmentID: segmentID)
            case let .some(.task(taskID)):
                stopTimer(taskID: taskID)
            case .none:
                stopTimer()
            }
            guard didStop else {
                return .rejected
            }
            if routesAfterSystemAction {
                closeTaskDetailNavigation()
                desktopDestination = .today
            }
            return .handled
        case .newTask:
            guard presentationRouter.presentNewTask(
                using: self,
                preservingDestination: .tasks
            ) else {
                return .deferred
            }
            closeTaskDetailNavigation()
            desktopDestination = .tasks
            return .handled
        case let .openTask(taskID):
            guard isTaskDetailRouteValid(taskID) else {
                return .rejected
            }
            openTaskDetail(taskID)
            return .handled
        }
    }
}
