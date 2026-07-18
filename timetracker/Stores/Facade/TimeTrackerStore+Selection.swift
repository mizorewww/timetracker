import Foundation

extension TimeTrackerStore {
    var selectedTask: TaskNode? {
        selectionCoordinator.selectedTask(selectedTaskID: selectedTaskID, taskByID: taskByID)
    }

    func selectTask(_ taskID: UUID, revealInToday: Bool = true) {
        selectedTaskID = taskID
        if revealInToday {
            tasksRoute = nil
            desktopDestination = .today
        }
        selectedTaskPulseID = taskID
        selectedTaskPulseToken = UUID()
    }

    func openTaskDetail(_ taskID: UUID) {
        guard isTaskDetailRouteValid(taskID) else { return }
        tasksRoute = .detail(taskID: taskID)
        selectTask(taskID, revealInToday: false)
        desktopDestination = .tasks
    }

    func openTaskEditor(_ taskID: UUID) {
        guard isTaskDetailRouteValid(taskID) else { return }
        tasksRoute = .editor(taskID: taskID)
        selectTask(taskID, revealInToday: false)
        desktopDestination = .tasks
    }

    func closeTaskDetailNavigation() {
        tasksRoute = nil
    }

    func isTaskDetailRouteValid(_ taskID: UUID) -> Bool {
        guard let task = task(for: taskID) else { return false }
        return task.deletedAt == nil
    }

    func ancestorTaskIDs(for taskID: UUID) -> [UUID] {
        selectionCoordinator.ancestorTaskIDs(for: taskID, taskByID: taskByID)
    }

    func affectedAncestorIDs(for taskID: UUID?, parentID: UUID? = nil) -> Set<UUID> {
        selectionCoordinator.affectedAncestorIDs(for: taskID, parentID: parentID, taskByID: taskByID)
    }

}
