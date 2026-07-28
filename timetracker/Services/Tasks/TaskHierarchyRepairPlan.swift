import Foundation

nonisolated struct TaskHierarchyRepairPlan: Equatable {
    let cycleBreakerTaskIDs: Set<UUID>
    let taskIDsToDisplayAsRoots: Set<UUID>

    init(tasks: [TaskNode]) {
        self.init(canonicalTasks: tasks.deduplicatedByID())
    }

    init(canonicalTasks: [TaskNode]) {
        let visibleTasks = canonicalTasks.filter { $0.deletedAt == nil }
        let taskByID = visibleTasks.reduce(into: [UUID: TaskNode]()) { result, task in
            result[task.id] = task
        }
        let missingParentTaskIDs = Set(
            visibleTasks.compactMap { task -> UUID? in
                guard let parentID = task.parentID else { return nil }
                return taskByID[parentID] == nil ? task.id : nil
            }
        )
        var cycleBreakers = Set<UUID>()
        var processed = Set<UUID>()

        for startID in taskByID.keys.sorted(by: { $0.uuidString < $1.uuidString }) where !processed.contains(startID) {
            var path: [UUID] = []
            var indexByID: [UUID: Int] = [:]
            var cursor: UUID? = startID

            while let currentID = cursor,
                  let current = taskByID[currentID],
                  !processed.contains(currentID)
            {
                if let cycleStart = indexByID[currentID] {
                    let cycle = path[cycleStart...]
                    if let breaker = cycle.min(by: { $0.uuidString < $1.uuidString }) {
                        cycleBreakers.insert(breaker)
                    }
                    break
                }
                indexByID[currentID] = path.count
                path.append(currentID)
                cursor = current.parentID
            }
            processed.formUnion(path)
        }

        cycleBreakerTaskIDs = cycleBreakers
        taskIDsToDisplayAsRoots = missingParentTaskIDs.union(cycleBreakers)
    }
}
