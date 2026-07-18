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
/// Archived or deleted branches are hidden and cannot receive new work. Legacy
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
        return TaskWorkEligibility(
            visibleTaskIDs: allTaskIDs.subtracting(hiddenTaskIDs),
            trackableTaskIDs: allTaskIDs.subtracting(hiddenTaskIDs)
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
