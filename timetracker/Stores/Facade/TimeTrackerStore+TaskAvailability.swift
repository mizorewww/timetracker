import Foundation

extension TimeTrackerStore {
    func isTaskAvailableForTracking(_ task: TaskNode) -> Bool {
        trackableTaskIDs.contains(task.id)
    }

    func isTaskEligibleAsParent(_ task: TaskNode) -> Bool {
        parentEligibleTaskIDs.contains(task.id)
    }

    func isTaskVisible(_ task: TaskNode) -> Bool {
        visibleTaskIDs.contains(task.id)
    }

    func isTaskRecurrenceTemplate(_ task: TaskNode) -> Bool {
        taskRecurrenceRules.contains {
            $0.deletedAt == nil && $0.templateTaskID == task.id
        } || taskRecurrenceOccurrences.contains {
            $0.deletedAt == nil && $0.templateTaskID == task.id
        }
    }
}
