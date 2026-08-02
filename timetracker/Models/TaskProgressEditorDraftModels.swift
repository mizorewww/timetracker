import Foundation

nonisolated struct TaskQuantityGoalDraft: Codable, Equatable, Sendable {
    var targetAmount: Int
    var unitLabel: String

    init(targetAmount: Int = 1, unitLabel: String = "") {
        self.targetAmount = targetAmount
        self.unitLabel = unitLabel
    }

    nonisolated init(goal: TaskQuantityGoal) {
        targetAmount = goal.targetAmount
        unitLabel = goal.unitLabel
    }
}

nonisolated struct TaskDailyRecurrenceDraft:
    Codable,
    Equatable,
    Sendable
{
    var isEnabled: Bool
    var startDayKey: String
    var timeZoneIdentifier: String

    init(
        isEnabled: Bool = true,
        startDayKey: String,
        timeZoneIdentifier: String
    ) {
        self.isEnabled = isEnabled
        self.startDayKey = startDayKey
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    init(
        startingAt date: Date = Date(),
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        isEnabled = true
        startDayKey = TaskRecurrenceDayKey.value(
            for: date,
            timeZone: timeZone
        )
        timeZoneIdentifier = timeZone.identifier
    }

    nonisolated init(rule: TaskRecurrenceRule) {
        isEnabled = rule.isEnabled
        startDayKey = rule.startDayKey
        timeZoneIdentifier = rule.timeZoneIdentifier
    }
}

enum TaskQuantityEntryRevision {
    private static let domain =
        "timetracker.task-quantity-entry-revision.v1"

    @MainActor
    static func value(
        taskID: UUID,
        entries: [TaskQuantityEntry]
    ) -> UUID {
        let components = entries
            .filter { $0.taskID == taskID }
            .visibleDeduplicatedByID()
            .map {
                $0.id.uuidString.lowercased() + ":" +
                    $0.clientMutationID.uuidString.lowercased()
            }
            .sorted()
        return DeterministicUUID.version8(
            domain: domain,
            components: [taskID.uuidString.lowercased()] +
                components
        )
    }
}
