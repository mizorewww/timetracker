import Foundation

extension TimeTrackerStore {
    var selectedTask: TaskNode? {
        selectionCoordinator.selectedTask(selectedTaskID: selectedTaskID, taskByID: taskByID)
    }

    func selectTask(_ taskID: UUID, revealInToday: Bool = true) {
        selectedTaskID = taskID
        if revealInToday {
            desktopDestination = .today
        }
        selectedTaskPulseID = taskID
        selectedTaskPulseToken = UUID()
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
