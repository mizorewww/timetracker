import Foundation

extension RollupIncrementalIndex {
    func makeChecklistProgress(
        taskIDs: Set<UUID>,
        checklistItems: [ChecklistItem]
    ) -> [UUID: ChecklistProgress] {
        let grouped = Dictionary(
            grouping: checklistItems.visibleDeduplicatedByID(),
            by: \.taskID
        )
        return taskIDs.reduce(into: [:]) { result, taskID in
            result[taskID] = progress(taskID: taskID, items: grouped[taskID] ?? [])
        }
    }

    func progress(taskID: UUID, items: [ChecklistItem]) -> ChecklistProgress {
        let canonical = items.visibleDeduplicatedByID().filter { $0.taskID == taskID }
        return ChecklistProgress(
            taskID: taskID,
            totalCount: canonical.count,
            completedCount: canonical.lazy.filter(\.isCompleted).count
        )
    }

    func ancestorIDs(of taskID: UUID) -> [UUID] {
        var result: [UUID] = []
        var cursor = parentByTaskID[taskID]
        var visited = Set<UUID>()
        while let current = cursor, visited.insert(current).inserted {
            result.append(current)
            cursor = parentByTaskID[current]
        }
        return result
    }

    func makeDepths() -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for startID in taskByID.keys where result[startID] == nil {
            var chain: [UUID] = []
            var visited = Set<UUID>()
            var cursor: UUID? = startID
            while let current = cursor,
                  result[current] == nil,
                  visited.insert(current).inserted
            {
                chain.append(current)
                cursor = parentByTaskID[current]
            }

            var depth = cursor.flatMap { result[$0] } ?? -1
            for taskID in chain.reversed() {
                depth += 1
                result[taskID] = depth
            }
        }
        return result
    }

    func makePostorderTaskIDs(taskIDs: Set<UUID>) -> [UUID] {
        var stateByID: [UUID: UInt8] = [:]
        var result: [UUID] = []
        for startID in taskIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard stateByID[startID] == nil else { continue }
            var stack: [(id: UUID, expanded: Bool)] = [(startID, false)]
            while let entry = stack.popLast() {
                if entry.expanded {
                    guard stateByID[entry.id] != 2 else { continue }
                    stateByID[entry.id] = 2
                    result.append(entry.id)
                    continue
                }
                guard stateByID[entry.id] == nil else { continue }
                stateByID[entry.id] = 1
                stack.append((entry.id, true))
                let children = (childrenByParent[entry.id] ?? [])
                    .map(\.id)
                    .filter { taskIDs.contains($0) && stateByID[$0] == nil }
                    .sorted { $0.uuidString > $1.uuidString }
                stack.append(contentsOf: children.map { ($0, false) })
            }
        }
        return result
    }
}
