import Foundation

enum AppDeepLinkHandlingDisposition: Equatable {
    case handled
    case deferred
    case rejected
}

extension TimeTrackerStore {
    func handleDeepLink(
        _ url: URL,
        presentationRouter: AppPresentationRouter
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
        case .open(let destination):
            closeTaskDetailNavigation()
            desktopDestination = destination
            return .handled
        case .startTimerPicker:
            guard presentationRouter.presentStartTaskPicker() else { return .deferred }
            closeTaskDetailNavigation()
            desktopDestination = .today
            return .handled
        case .startTimer(let taskID):
            guard let task = task(for: taskID), isTaskAvailableForTracking(task) else {
                return .rejected
            }
            closeTaskDetailNavigation()
            desktopDestination = .today
            startTask(task)
            return .handled
        case .stopTimer(let taskID):
            let segment: TimeSegment?
            if let taskID {
                segment = activeSegment(for: taskID)
            } else {
                segment = activeSegments.last
            }
            guard let segment else { return .rejected }
            closeTaskDetailNavigation()
            desktopDestination = .today
            stop(segment: segment)
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
        case .openTask(let taskID):
            guard let task = task(for: taskID), task.deletedAt == nil else {
                return .rejected
            }
            openTaskDetail(taskID)
            return .handled
        }
    }
}
