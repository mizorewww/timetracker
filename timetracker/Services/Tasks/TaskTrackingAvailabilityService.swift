import Foundation

struct TaskWorkEligibility: Equatable {
    let visibleTaskIDs: Set<UUID>
    let trackableTaskIDs: Set<UUID>
}

enum TaskParentChangeBlocker: Equatable {
    case completed
    case archived
    case deleted
}

/// Resolves visibility and work eligibility for an entire hierarchy in linear
/// time without rewriting descendants' own workflow statuses.
///
/// Archived or deleted branches are hidden. Completed branches stay visible so
/// their detail and history remain reachable, but they cannot receive new work
/// until every completed task on the path is reopened.
struct TaskTrackingAvailabilityService {
    func eligibility(tasks: [TaskNode]) -> TaskWorkEligibility {
        let canonicalTasks = tasks.deduplicatedByID()
        let allTaskIDs = Set(canonicalTasks.map(\.id))
        let childIDsByParentID = Dictionary(grouping: canonicalTasks, by: \TaskNode.parentID)
            .mapValues { children in children.map(\.id) }

        let hiddenTaskIDs = descendantClosure(
            startingWith: Set(
                canonicalTasks.lazy
                    .filter { $0.deletedAt != nil || $0.status == .archived }
                    .map(\.id)
            ),
            childIDsByParentID: childIDsByParentID
        )
        let completedTaskIDs = Set(
            canonicalTasks.lazy
                .filter { $0.status == .completed }
                .map(\.id)
        )
        let workBlockedTaskIDs = descendantClosure(
            startingWith: hiddenTaskIDs.union(completedTaskIDs),
            childIDsByParentID: childIDsByParentID
        )

        return TaskWorkEligibility(
            visibleTaskIDs: allTaskIDs.subtracting(hiddenTaskIDs),
            trackableTaskIDs: allTaskIDs.subtracting(workBlockedTaskIDs)
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
    /// lifecycle still accepts edits. This intentionally differs from work
    /// eligibility, which also inherits completed and archived ancestors.
    func parentChangeBlocker(for task: TaskNode) -> TaskParentChangeBlocker? {
        if task.deletedAt != nil {
            return .deleted
        }
        switch task.status {
        case .completed:
            return .completed
        case .archived:
            return .archived
        case .planned, .active:
            return nil
        }
    }

    func completedBlockingTaskIDs(for taskID: UUID, tasks: [TaskNode]) -> [UUID] {
        let taskByID = tasks.deduplicatedByID().latestByID()
        var currentID: UUID? = taskID
        var visited = Set<UUID>()
        var result: [UUID] = []

        while let candidateID = currentID,
              visited.insert(candidateID).inserted,
              let task = taskByID[candidateID] {
            if task.deletedAt != nil || task.status == .archived {
                return []
            }
            if task.status == .completed {
                result.append(candidateID)
            }
            currentID = task.parentID
        }

        return Array(result.reversed())
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
