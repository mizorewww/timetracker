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
        guard let route = prepareTaskDetailRoute(taskID) else { return }
        tasksRoute = route
        desktopDestination = .tasks
    }

    func openTaskEditor(_ taskID: UUID) {
        guard let route = prepareTaskDetailRoute(taskID, startsEditing: true) else { return }
        tasksRoute = route
        desktopDestination = .tasks
    }

    func prepareTaskDetailRoute(
        _ taskID: UUID,
        startsEditing: Bool = false
    ) -> TasksRoute? {
        guard isTaskDetailRouteValid(taskID) else { return nil }
        selectTask(taskID, revealInToday: false)
        return startsEditing
            ? .editor(taskID: taskID)
            : .detail(taskID: taskID)
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
