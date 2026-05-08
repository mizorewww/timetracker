import Foundation

struct StoreSelectionCoordinator {
    func selectedTask(selectedTaskID: UUID?, taskByID: [UUID: TaskNode]) -> TaskNode? {
        guard let selectedTaskID else { return nil }
        return taskByID[selectedTaskID]
    }

    func ancestorTaskIDs(for taskID: UUID, taskByID: [UUID: TaskNode]) -> [UUID] {
        var result: [UUID] = []
        var cursor = taskByID[taskID]
        var visited: Set<UUID> = []

        while let parentID = cursor?.parentID, !visited.contains(parentID) {
            result.append(parentID)
            visited.insert(parentID)
            cursor = taskByID[parentID]
        }

        return result
    }

    func affectedAncestorIDs(
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
