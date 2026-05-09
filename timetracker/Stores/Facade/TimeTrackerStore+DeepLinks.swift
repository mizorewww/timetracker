import Foundation

extension TimeTrackerStore {
    func handleDeepLink(_ url: URL) {
        let router = AppDeepLinkRouter()
        guard let action = router.action(for: url) else { return }

        switch action {
        case .open(let destination):
            desktopDestination = destination
        case .startTimerPicker:
            desktopDestination = .today
            isStartTaskPickerPresented = true
        case .startTimer(let taskID):
            guard let task = task(for: taskID), task.deletedAt == nil, task.status != .archived else { return }
            desktopDestination = .today
            startTask(task)
        case .stopTimer(let taskID):
            desktopDestination = .today
            guard let segment = taskID.flatMap({ id in
                activeSegments.first { $0.taskID == id }
            }) ?? activeSegments.first else { return }
            stop(segment: segment)
        case .newTask:
            desktopDestination = .tasks
            presentNewTask(preservingDestination: .tasks)
        }
    }
}
