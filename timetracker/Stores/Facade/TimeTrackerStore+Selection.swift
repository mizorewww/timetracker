import Foundation

extension TimeTrackerStore {
    var selectedTask: TaskNode? {
        selectionCoordinator.selectedTask(selectedTaskID: selectedTaskID, taskByID: taskByID)
    }

    func selectTask(_ taskID: UUID, revealInToday: Bool = true) {
        selectedTaskID = taskID
        if revealInToday {
            desktopTaskDetailID = nil
            desktopDestination = .today
        }
        selectedTaskPulseID = taskID
        selectedTaskPulseToken = UUID()
    }

    func openTaskDetail(_ taskID: UUID) {
        desktopTaskDetailID = taskID
        selectTask(taskID, revealInToday: false)
        desktopDestination = .tasks
    }

    func closeTaskDetailNavigation() {
        desktopTaskDetailID = nil
    }

    func ancestorTaskIDs(for taskID: UUID) -> [UUID] {
        selectionCoordinator.ancestorTaskIDs(for: taskID, taskByID: taskByID)
    }

    func affectedAncestorIDs(for taskID: UUID?, parentID: UUID? = nil) -> Set<UUID> {
        selectionCoordinator.affectedAncestorIDs(for: taskID, parentID: parentID, taskByID: taskByID)
    }

    func affectedTaskIDsForHierarchyChange(taskID: UUID?, parentID: UUID? = nil) -> Set<UUID> {
        guard let taskID else { return [] }
        return affectedAncestorIDs(for: taskID, parentID: parentID)
            .union(taskTreeService.descendantIDs(of: taskID, tasks: tasks))
            .union([taskID])
    }
}
