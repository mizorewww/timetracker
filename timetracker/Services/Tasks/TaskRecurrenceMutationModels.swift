import Foundation

enum TaskRecurrenceMutationError: LocalizedError, Equatable {
    case invalidStartDay
    case invalidTimeZone
    case templateUnavailable
    case templateHasActiveWork
    case ruleUnavailable
    case ruleChanged
    case immutableRuleConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidStartDay:
            AppStrings.localized("task.recurrence.error.invalidStartDay")
        case .invalidTimeZone:
            AppStrings.localized("task.recurrence.error.invalidTimeZone")
        case .templateUnavailable:
            AppStrings.localized("task.recurrence.error.templateUnavailable")
        case .templateHasActiveWork:
            AppStrings.localized(
                "task.recurrence.error.templateHasActiveWork"
            )
        case .ruleUnavailable:
            AppStrings.localized("task.recurrence.error.ruleUnavailable")
        case .ruleChanged:
            AppStrings.localized("task.recurrence.error.ruleChanged")
        case .immutableRuleConfiguration:
            AppStrings.localized(
                "task.recurrence.error.immutableConfiguration"
            )
        }
    }
}

struct TaskRecurrenceRuleMutationBaseline: Equatable {
    let ruleID: UUID
    let templateTaskID: UUID
    let clientMutationID: UUID

    init(rule: TaskRecurrenceRule) {
        ruleID = rule.id
        templateTaskID = rule.templateTaskID
        clientMutationID = rule.clientMutationID
    }
}

struct TaskRecurrenceMaterializationMutation: Equatable {
    let ruleID: UUID
    let templateTaskID: UUID
    let occurrenceID: UUID
    let generatedTaskID: UUID
    let generatedQuantityGoalID: UUID?
    let affectedAncestorTaskIDs: Set<UUID>
}

struct TaskRecurrenceMutationOutcome: Equatable {
    var changedRuleTemplateTaskIDs = Set<UUID>()
    var changedRuleAncestorTaskIDsByTemplateID:
        [UUID: Set<UUID>] = [:]
    var materializations: [TaskRecurrenceMaterializationMutation] = []

    var didMutate: Bool {
        changedRuleTemplateTaskIDs.isEmpty == false ||
            materializations.isEmpty == false
    }

    var events: Set<StoreDomainEvent> {
        var result = Set(
            changedRuleTemplateTaskIDs.map {
                StoreDomainEvent.taskChanged(
                    taskID: $0,
                    affectedAncestorIDs:
                    changedRuleAncestorTaskIDsByTemplateID[$0] ?? []
                )
            }
        )
        for materialization in materializations {
            result.insert(
                .taskChanged(
                    taskID: materialization.generatedTaskID,
                    affectedAncestorIDs:
                    materialization.affectedAncestorTaskIDs
                )
            )
        }
        return result
    }

    static let noChanges = TaskRecurrenceMutationOutcome()

    mutating func markRuleChanged(
        templateTaskID: UUID,
        affectedAncestorTaskIDs: Set<UUID>
    ) {
        changedRuleTemplateTaskIDs.insert(templateTaskID)
        changedRuleAncestorTaskIDsByTemplateID[templateTaskID] =
            affectedAncestorTaskIDs
    }
}

enum TaskRecurrenceMutationCheckpoint: Equatable {
    case ruleCreated(UUID)
    case ruleUpdated(UUID)
    case generatedTaskCreated(UUID)
    case quantityGoalCreated(UUID)
    case occurrenceCreated(UUID)
}
