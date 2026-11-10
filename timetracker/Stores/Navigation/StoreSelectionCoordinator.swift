import Foundation

enum StoreSelectionCoordinator {
    static func selectedTask(selectedTaskID: UUID?, taskByID: [UUID: TaskNode]) -> TaskNode? {
        guard let selectedTaskID else { return nil }
        return taskByID[selectedTaskID]
    }

    static func ancestorTaskIDs(for taskID: UUID, taskByID: [UUID: TaskNode]) -> [UUID] {
        TaskTreeService.ancestorIDs(of: taskID, taskByID: taskByID)
    }

    static func affectedAncestorIDs(
        for taskID: UUID?,
        parentID: UUID? = nil,
        taskByID: [UUID: TaskNode]
    ) -> Set<UUID> {
        var ids: Set<UUID> = []
        if let taskID {
            ids.formUnion(ancestorTaskIDs(for: taskID, taskByID: taskByID))
        }
        if let parentID {
            ids.insert(parentID)
            ids.formUnion(ancestorTaskIDs(for: parentID, taskByID: taskByID))
        }
        return ids
    }
}
