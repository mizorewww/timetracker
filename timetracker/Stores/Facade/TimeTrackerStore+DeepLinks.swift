import Foundation

extension TimeTrackerStore {
    func handleDeepLink(_ url: URL) {
        let router = AppDeepLinkRouter()
        guard let action = router.action(for: url) else { return }

        switch action {
        case .open(let destination):
            closeTaskDetailNavigation()
            desktopDestination = destination
        case .startTimerPicker:
            closeTaskDetailNavigation()
            desktopDestination = .today
            isStartTaskPickerPresented = true
        case .startTimer(let taskID):
            guard let task = task(for: taskID), isTaskAvailableForTracking(task) else { return }
            closeTaskDetailNavigation()
            desktopDestination = .today
            startTask(task)
        case .stopTimer(let taskID):
            closeTaskDetailNavigation()
            desktopDestination = .today
            guard let segment = taskID.flatMap({ id in
                activeSegment(for: id)
            }) ?? activeSegments.last else { return }
            stop(segment: segment)
        case .newTask:
            closeTaskDetailNavigation()
            desktopDestination = .tasks
            presentNewTask(preservingDestination: .tasks)
        case .openTask(let taskID):
            guard let task = task(for: taskID), task.deletedAt == nil else { return }
            openTaskDetail(taskID)
        }
    }
}
