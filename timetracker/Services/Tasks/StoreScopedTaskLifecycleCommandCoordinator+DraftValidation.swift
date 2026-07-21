import Foundation
import SwiftData

extension StoreScopedTaskLifecycleCommandCoordinator {
    static func validateDraft(
        _ draft: TaskEditorDraft,
        existingTask: TaskNode?,
        tasks: [TaskNode],
        taskRepository: SwiftDataTaskRepository,
        context: ModelContext
    ) throws {
        if let existingTask {
            guard let baseline = draft.baseline,
                  baseline.taskMutationID == existingTask.clientMutationID,
                  try baselineMatchesCurrentRelatedModels(
                    baseline,
                    taskID: existingTask.id,
                    quantityGoalDraft: draft.quantityGoal,
                    confirmsQuantityProgressReset:
                        draft.confirmsQuantityProgressReset,
                    taskRepository: taskRepository,
                    context: context
                  ) else {
                throw TaskLifecycleMutationError.staleDraft
            }
        }

        let parentIsChanging = existingTask?.parentID != draft.parentID
        if let existingTask, parentIsChanging,
           let blocker = TaskTrackingAvailabilityService()
            .parentChangeBlocker(for: existingTask) {
            throw TaskLifecycleMutationError.parentChangeBlocked(blocker)
        }
        if let parentID = draft.parentID,
           parentIsChanging,
           TaskTrackingAvailabilityService()
            .trackableTaskIDs(tasks: tasks)
            .contains(parentID) == false {
            throw TaskLifecycleMutationError.parentUnavailable
        }

        if draft.parentID == nil,
           let categoryID = draft.categoryID,
           try taskRepository.category(id: categoryID) == nil {
            throw TaskLifecycleMutationError.staleDraft
        }
    }

    private static func baselineMatchesCurrentRelatedModels(
        _ baseline: TaskEditorDraftBaseline,
        taskID: UUID,
        quantityGoalDraft: TaskQuantityGoalDraft?,
        confirmsQuantityProgressReset: Bool,
        taskRepository: SwiftDataTaskRepository,
        context: ModelContext
    ) throws -> Bool {
        let requestedTaskID = taskID
        let checklistItems = try context.fetch(
            FetchDescriptor<ChecklistItem>(
                predicate: #Predicate { $0.taskID == requestedTaskID }
            )
        ).visibleDeduplicatedByID()
        let checklistItemMutationIDs = checklistItems.reduce(
            into: [UUID: UUID]()
        ) {
            $0[$1.id] = $1.clientMutationID
        }
        guard checklistItemMutationIDs ==
                baseline.checklistItemMutationIDs else {
            return false
        }

        let checklistItemIDs = Array(checklistItemMutationIDs.keys)
        let visualMutationIDs: [UUID: UUID]
        if checklistItemIDs.isEmpty {
            visualMutationIDs = [:]
        } else {
            visualMutationIDs = try context.fetch(
                FetchDescriptor<ChecklistItemVisual>(
                    predicate: #Predicate {
                        checklistItemIDs.contains($0.checklistItemID)
                    }
                )
            )
            .deduplicatedByID()
            .logicalWinnersByChecklistItemID()
            .reduce(into: [:]) { result, pair in
                guard pair.value.deletedAt == nil else { return }
                result[pair.key] = pair.value.clientMutationID
            }
        }
        guard visualMutationIDs ==
                baseline.checklistVisualMutationIDs else {
            return false
        }

        let categoryAssignment = try taskRepository
            .categoryAssignments()
            .logicalWinnersByTaskID()[taskID]
        let categoryAssignmentMutationID = categoryAssignment?.deletedAt == nil
            ? categoryAssignment?.clientMutationID
            : nil
        guard categoryAssignmentMutationID ==
                baseline.categoryAssignmentMutationID else {
            return false
        }

        let quantityGoalState = try quantityGoalState(
            taskID: taskID,
            context: context
        )
        guard quantityGoalState.activeMutationID ==
                baseline.quantityGoalMutationID else {
            return false
        }
        let willTombstoneEntries = (
            baseline.quantityGoalMutationID != nil &&
                quantityGoalDraft == nil &&
                confirmsQuantityProgressReset
        ) || (
            baseline.quantityGoalMutationID == nil &&
                quantityGoalDraft != nil &&
                quantityGoalState.hasDeletedRow
        )
        if willTombstoneEntries {
            let currentRevision = try quantityEntryRevision(
                taskID: taskID,
                context: context
            )
            let baselineRevision = baseline.quantityEntryRevision ??
                TaskQuantityEntryRevision.value(
                    taskID: taskID,
                    entries: []
                )
            guard currentRevision == baselineRevision else {
                return false
            }
        }
        return try recurrenceRuleMutationID(
            taskID: taskID,
            context: context
        ) == baseline.recurrenceRuleMutationID
    }

    private static func recurrenceRuleMutationID(
        taskID: UUID,
        context: ModelContext
    ) throws -> UUID? {
        let requestedTaskID = taskID
        let rows = try context.fetch(
            FetchDescriptor<TaskRecurrenceRule>(
                predicate: #Predicate {
                    $0.templateTaskID == requestedTaskID
                }
            )
        )
        let rule = rows.latestByID()[
            TaskProgressIdentity.recurrenceRuleID(
                templateTaskID: taskID
            )
        ]
        return rule?.deletedAt == nil ? rule?.clientMutationID : nil
    }

}
