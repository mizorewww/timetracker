import Foundation

struct TaskWorkEligibility: Equatable {
    let visibleTaskIDs: Set<UUID>
    let trackableTaskIDs: Set<UUID>
}

nonisolated enum TaskParentChangeBlocker: Equatable {
    case archived
    case deleted
}

/// Resolves visibility and work eligibility for an entire hierarchy in linear
/// time.
///
/// Archived or deleted branches are hidden and cannot receive new work. Apple
/// Health branches stay visible, but are sync-only. Legacy
/// planned/active/completed raw values are inert compatibility bytes.
struct TaskTrackingAvailabilityService {
    func eligibility(tasks: [TaskNode]) -> TaskWorkEligibility {
        let canonicalTasks = tasks.deduplicatedByID()
        let allTaskIDs = Set(canonicalTasks.map(\.id))
        let childIDsByParentID = Dictionary(grouping: canonicalTasks, by: \TaskNode.parentID)
            .mapValues { children in children.map(\.id) }

        let hiddenTaskIDs = descendantClosure(
            startingWith: Set(
                canonicalTasks.lazy
                    .filter { $0.deletedAt != nil || $0.isArchivedForLifecycle }
                    .map(\.id)
            ),
            childIDsByParentID: childIDsByParentID
        )
        // Keep the complete fixed-ID seed set. During a partial CloudKit merge,
        // a child can arrive before its generated Health parent.
        let syncOnlyTaskIDs = descendantClosure(
            startingWith: AppleHealthTaskCatalog.syncOnlyTaskIDs,
            childIDsByParentID: childIDsByParentID
        )
        let visibleTaskIDs = allTaskIDs.subtracting(hiddenTaskIDs)
        return TaskWorkEligibility(
            visibleTaskIDs: visibleTaskIDs,
            trackableTaskIDs: visibleTaskIDs.subtracting(syncOnlyTaskIDs)
        )
    }

    func visibleTaskIDs(tasks: [TaskNode]) -> Set<UUID> {
        eligibility(tasks: tasks).visibleTaskIDs
    }

    func trackableTaskIDs(tasks: [TaskNode]) -> Set<UUID> {
        eligibility(tasks: tasks).trackableTaskIDs
    }

    /// Compatibility name for system surfaces that already interpret
    /// "available" as "can accept new time/work".
    func availableTaskIDs(tasks: [TaskNode]) -> Set<UUID> {
        trackableTaskIDs(tasks: tasks)
    }

    /// A task can leave an unavailable ancestor branch as long as its own
    /// lifecycle still accepts edits.
    func parentChangeBlocker(for task: TaskNode) -> TaskParentChangeBlocker? {
        if task.deletedAt != nil {
            return .deleted
        }
        if task.isArchivedForLifecycle {
            return .archived
        }
        return nil
    }

    func hasArchivedAncestor(
        of task: TaskNode,
        taskByID: [UUID: TaskNode],
        taskIDsToDisplayAsRoots: Set<UUID>
    ) -> Bool {
        var visited = Set<UUID>()
        var cursor = task
        while taskIDsToDisplayAsRoots.contains(cursor.id) == false,
              let currentID = cursor.parentID,
              visited.insert(currentID).inserted,
              let parent = taskByID[currentID] {
            if parent.isArchivedForLifecycle {
                return true
            }
            cursor = parent
        }
        return false
    }

    private func descendantClosure(
        startingWith seedIDs: Set<UUID>,
        childIDsByParentID: [UUID?: [UUID]]
    ) -> Set<UUID> {
        var result = seedIDs
        var pending = Array(seedIDs)

        while let taskID = pending.popLast() {
            for childID in childIDsByParentID[taskID] ?? [] {
                if result.insert(childID).inserted {
                    pending.append(childID)
                }
            }
        }

        return result
    }
}
