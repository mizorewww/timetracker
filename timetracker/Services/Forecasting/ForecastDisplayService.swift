import Foundation

struct ForecastDisplayItem: Identifiable, Equatable {
    let taskID: UUID
    let rollup: TaskRollup

    var id: UUID { taskID }
}

struct ForecastDisplayService {
    func displayItems(tasks: [TaskNode], rollups: [UUID: TaskRollup], limit: Int? = nil) -> [ForecastDisplayItem] {
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let childrenByParent = Dictionary(grouping: visibleTasks(tasks), by: \.parentID)
        let roots = (childrenByParent[nil] ?? []).sorted(by: taskSort)
        var emitted = Set<UUID>()
        var items: [ForecastDisplayItem] = []

        func append(_ item: ForecastDisplayItem) {
            guard emitted.insert(item.taskID).inserted else { return }
            items.append(item)
        }

        func visit(_ task: TaskNode) {
            guard isVisible(task), let rollup = rollups[task.id] else {
                for child in (childrenByParent[task.id] ?? []).sorted(by: taskSort) {
                    visit(child)
                }
                return
            }

            if rollup.isDisplayableForecast {
                if rollup.checklistProgress.totalCount > 0 {
                    append(ForecastDisplayItem(taskID: task.id, rollup: rollup))
                    return
                }

                let sourceIDs = rollup.forecastSourceTaskIDs.filter { sourceID in
                    guard let source = taskByID[sourceID] else { return false }
                    return isVisible(source)
                }
                if sourceIDs.count == 1,
                   let sourceID = sourceIDs.first,
                   let sourceTask = taskByID[sourceID],
                   let sourceRollup = rollups[sourceTask.id],
                   sourceRollup.isDisplayableForecast {
                    append(ForecastDisplayItem(taskID: sourceTask.id, rollup: sourceRollup))
                    return
                }

                append(ForecastDisplayItem(taskID: task.id, rollup: rollup))
                return
            }

            for child in (childrenByParent[task.id] ?? []).sorted(by: taskSort) {
                visit(child)
            }
        }

        for root in roots {
            visit(root)
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
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        guard let task = taskByID[taskID], isVisible(task), let rollup = rollups[taskID] else { return nil }
        if rollup.isDisplayableForecast, rollup.checklistProgress.totalCount > 0 {
            return ForecastDisplayItem(taskID: taskID, rollup: rollup)
        }
        if rollup.checklistProgress.totalCount > 0 {
            return nil
        }
        if rollup.isDisplayableForecast,
           rollup.forecastSourceTaskIDs.count > 1 {
            return ForecastDisplayItem(taskID: taskID, rollup: rollup)
        }
        if let sourceID = rollup.forecastSourceTaskIDs.first,
           let source = taskByID[sourceID],
           isVisible(source),
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
        task.deletedAt == nil && task.status != .archived && task.status != .completed
    }

    private func taskSort(_ lhs: TaskNode, _ rhs: TaskNode) -> Bool {
        if lhs.sortOrder == rhs.sortOrder {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.sortOrder < rhs.sortOrder
    }
}
