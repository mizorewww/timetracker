import Foundation

struct ForecastDisplayItem: Identifiable, Equatable {
    let taskID: UUID
    let rollup: TaskRollup

    var id: UUID { taskID }
}

struct ForecastDisplayService {
    func displayItems(tasks: [TaskNode], rollups: [UUID: TaskRollup], limit: Int? = nil) -> [ForecastDisplayItem] {
        let tasks = tasks.deduplicatedByID()
        let taskByID = tasks.latestByID()
        let childrenByParent = Dictionary(grouping: visibleTasks(tasks), by: \.parentID)
        let roots = (childrenByParent[nil] ?? []).sorted(by: taskSort)
        var emitted = Set<UUID>()
        var items: [ForecastDisplayItem] = []

        func append(_ item: ForecastDisplayItem) {
            guard emitted.insert(item.taskID).inserted else { return }
            items.append(item)
        }

        var pending = Array(roots.reversed())
        var visited = Set<UUID>()
        while let task = pending.popLast() {
            guard visited.insert(task.id).inserted else { continue }
            let children = (childrenByParent[task.id] ?? []).sorted(by: taskSort)
            guard isVisible(task), let rollup = rollups[task.id] else {
                pending.append(contentsOf: children.reversed())
                continue
            }

            if rollup.isDisplayableForecast {
                if rollup.checklistProgress.totalCount > 0 {
                    append(ForecastDisplayItem(taskID: task.id, rollup: rollup))
                    continue
                }

                let sourceIDs = rollup.forecastSourceTaskIDs.filter { sourceID in
                    isHierarchyVisible(sourceID, taskByID: taskByID)
                }
                if rollup.forecastSourceTaskCount == 1,
                   let sourceID = sourceIDs.first,
                   let sourceTask = taskByID[sourceID],
                   let sourceRollup = rollups[sourceTask.id],
                    sourceRollup.isDisplayableForecast {
                    append(ForecastDisplayItem(taskID: sourceTask.id, rollup: sourceRollup))
                    continue
                }

                append(ForecastDisplayItem(taskID: task.id, rollup: rollup))
                continue
            }

            pending.append(contentsOf: children.reversed())
        }

        let sorted = items.sorted {
            let leftRemaining = $0.rollup.remainingSeconds ?? 0
            let rightRemaining = $1.rollup.remainingSeconds ?? 0
            if leftRemaining != rightRemaining {
                return leftRemaining > rightRemaining
            }
            let leftUpdated = taskByID[$0.taskID]?.updatedAt ?? .distantPast
            let rightUpdated = taskByID[$1.taskID]?.updatedAt ?? .distantPast
            return leftUpdated > rightUpdated
        }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    func displayItem(for taskID: UUID, tasks: [TaskNode], rollups: [UUID: TaskRollup]) -> ForecastDisplayItem? {
        let taskByID = tasks.latestByID()
        guard isHierarchyVisible(taskID, taskByID: taskByID),
              let rollup = rollups[taskID] else {
            return nil
        }
        if rollup.isDisplayableForecast, rollup.checklistProgress.totalCount > 0 {
            return ForecastDisplayItem(taskID: taskID, rollup: rollup)
        }
        if rollup.checklistProgress.totalCount > 0 {
            return nil
        }
        if rollup.isDisplayableForecast,
           rollup.forecastSourceTaskCount > 1 {
            return ForecastDisplayItem(taskID: taskID, rollup: rollup)
        }
        if let sourceID = rollup.forecastSourceTaskIDs.first,
           isHierarchyVisible(sourceID, taskByID: taskByID),
           let sourceRollup = rollups[sourceID],
           sourceRollup.isDisplayableForecast {
            return ForecastDisplayItem(taskID: sourceID, rollup: sourceRollup)
        }
        return nil
    }

    private func visibleTasks(_ tasks: [TaskNode]) -> [TaskNode] {
        tasks.filter(isVisible)
    }

    private func isVisible(_ task: TaskNode) -> Bool {
        task.deletedAt == nil && !task.isArchivedForLifecycle
    }

    private func isHierarchyVisible(_ taskID: UUID, taskByID: [UUID: TaskNode]) -> Bool {
        var currentID: UUID? = taskID
        var visited = Set<UUID>()
        while let candidateID = currentID {
            guard visited.insert(candidateID).inserted,
                  let task = taskByID[candidateID],
                  isVisible(task) else {
                return false
            }
            currentID = task.parentID
        }
        return true
    }

    private func taskSort(_ lhs: TaskNode, _ rhs: TaskNode) -> Bool {
        if lhs.sortOrder == rhs.sortOrder {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.sortOrder < rhs.sortOrder
    }
}
