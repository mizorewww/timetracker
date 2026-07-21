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
        _ = taskReadModelRevision
        return taskDomainStore.incompleteRecurrenceTemplateTaskIDs
            .contains(task.id) || taskRecurrenceRules.contains {
            $0.deletedAt == nil && $0.templateTaskID == task.id
        } || taskRecurrenceOccurrences.contains {
            $0.deletedAt == nil && $0.templateTaskID == task.id
        }
    }

    func isGeneratedRecurrenceTask(taskID: UUID) -> Bool {
        _ = taskReadModelRevision
        return taskDomainStore.incompleteRecurrenceGeneratedTaskIDs
            .contains(taskID) || taskRecurrenceOccurrences.contains {
            $0.deletedAt == nil && $0.generatedTaskID == taskID
        }
    }

    func taskHasActiveWork(taskID: UUID) -> Bool {
        activeSegment(for: taskID) != nil ||
            activePomodoroRun(for: taskID) != nil
    }
}
