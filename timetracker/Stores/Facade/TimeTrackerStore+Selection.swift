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

    func prepareTaskDetailRoute(_ taskID: UUID) -> TasksRoute? {
        guard isTaskDetailRouteValid(taskID) else { return nil }
        selectTask(taskID, revealInToday: false)
        return .detail(taskID: taskID)
    }

    func closeTaskDetailNavigation() {
        tasksRoute = nil
    }

    func archiveTaskProtectingUnsavedChanges(_ taskID: UUID) {
        let activeTaskID = taskDetailNavigationGuard.activeTaskID
        let archiveInvalidatesActiveDetail = activeTaskID.map {
            $0 == taskID || ancestorTaskIDs(for: $0).contains(taskID)
        } ?? false

        guard archiveInvalidatesActiveDetail else {
            archiveSelectedTask(taskID: taskID)
            return
        }

        taskDetailNavigationGuard.requestNavigation(
            dismissingActiveDetail: true,
            beforeDiscardingChanges: { [weak self] in
                self?.archiveSelectedTask(taskID: taskID) == true
            }
        ) {}
    }

    func isTaskDetailRouteValid(_ taskID: UUID) -> Bool {
        guard let task = task(for: taskID) else { return false }
        return isTaskVisible(task)
    }

    func shouldRetainTaskDetailRoute(_ taskID: UUID) -> Bool {
        isTaskDetailRouteValid(taskID) ||
            taskDetailNavigationGuard.protectsUnsavedChanges(for: taskID)
    }

    func ancestorTaskIDs(for taskID: UUID) -> [UUID] {
        selectionCoordinator.ancestorTaskIDs(for: taskID, taskByID: taskByID)
    }

    func affectedAncestorIDs(for taskID: UUID?, parentID: UUID? = nil) -> Set<UUID> {
        selectionCoordinator.affectedAncestorIDs(for: taskID, parentID: parentID, taskByID: taskByID)
    }

}
