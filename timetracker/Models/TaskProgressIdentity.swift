import Foundation

nonisolated enum TaskProgressIdentity {
    private static let recurrenceRuleDomain =
        "timetracker.task-recurrence-rule.v1"
    private static let recurrenceOccurrenceDomain =
        "timetracker.task-recurrence-occurrence.v1"
    private static let generatedTaskDomain =
        "timetracker.task-recurrence-generated-task.v1"
    private static let quantityGoalDomain =
        "timetracker.task-quantity-goal.v1"

    static func recurrenceRuleID(templateTaskID: UUID) -> UUID {
        DeterministicUUID.version8(
            domain: recurrenceRuleDomain,
            components: [templateTaskID.uuidString.lowercased()]
        )
    }

    static func recurrenceOccurrenceID(
        ruleID: UUID,
        dayKey: String
    ) -> UUID {
        DeterministicUUID.version8(
            domain: recurrenceOccurrenceDomain,
            components: [
                ruleID.uuidString.lowercased(),
                dayKey,
            ]
        )
    }

    static func generatedTaskID(
        ruleID: UUID,
        dayKey: String
    ) -> UUID {
        DeterministicUUID.version8(
            domain: generatedTaskDomain,
            components: [
                ruleID.uuidString.lowercased(),
                dayKey,
            ]
        )
    }

    static func quantityGoalID(taskID: UUID) -> UUID {
        DeterministicUUID.version8(
            domain: quantityGoalDomain,
            components: [taskID.uuidString.lowercased()]
        )
    }
}
