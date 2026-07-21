import Foundation

nonisolated struct TaskQuantityGoalMutationBaseline:
    Equatable,
    Sendable
{
    let goalID: UUID
    let taskID: UUID
    let clientMutationID: UUID

    @MainActor
    init(goal: TaskQuantityGoal) {
        goalID = goal.id
        taskID = goal.taskID
        clientMutationID = goal.clientMutationID
    }

    init(
        goalID: UUID,
        taskID: UUID,
        clientMutationID: UUID
    ) {
        self.goalID = goalID
        self.taskID = taskID
        self.clientMutationID = clientMutationID
    }
}

nonisolated struct TaskQuantityEntryMutationBaseline:
    Equatable,
    Sendable
{
    let entryID: UUID
    let taskID: UUID
    let quantityGoalID: UUID
    let clientMutationID: UUID

    @MainActor
    init(entry: TaskQuantityEntry) {
        entryID = entry.id
        taskID = entry.taskID
        quantityGoalID = entry.quantityGoalID
        clientMutationID = entry.clientMutationID
    }

    init(
        entryID: UUID,
        taskID: UUID,
        quantityGoalID: UUID,
        clientMutationID: UUID
    ) {
        self.entryID = entryID
        self.taskID = taskID
        self.quantityGoalID = quantityGoalID
        self.clientMutationID = clientMutationID
    }
}

nonisolated struct TaskQuantityProgressSnapshot: Equatable, Sendable {
    let taskID: UUID
    let goalBaseline: TaskQuantityGoalMutationBaseline
    let targetAmount: Int64
    let unitLabel: String
    let totalAmount: Int64
    let entryCount: Int
    let entryRevision: UUID
    let isRecordingAllowed: Bool

    var remainingAmount: Int64 {
        max(targetAmount - totalAmount, 0)
    }

    var isComplete: Bool {
        totalAmount >= targetAmount
    }

    var fractionCompleted: Double {
        guard targetAmount > 0 else { return 0 }
        return min(max(Double(totalAmount) / Double(targetAmount), 0), 1)
    }
}

nonisolated enum TaskQuantityProgressReadState: Equatable, Sendable {
    case none
    case incomplete
    case available(TaskQuantityProgressSnapshot)
}

nonisolated struct TaskQuantityEntrySnapshot:
    Identifiable,
    Equatable,
    Sendable
{
    let id: UUID
    let baseline: TaskQuantityEntryMutationBaseline
    let amount: Int
    let recordedAt: Date

    init(
        id: UUID,
        baseline: TaskQuantityEntryMutationBaseline,
        amount: Int,
        recordedAt: Date
    ) {
        self.id = id
        self.baseline = baseline
        self.amount = amount
        self.recordedAt = recordedAt
    }

    @MainActor
    init(entry: TaskQuantityEntry) {
        self.init(
            id: entry.id,
            baseline: TaskQuantityEntryMutationBaseline(entry: entry),
            amount: entry.amount,
            recordedAt: entry.recordedAt
        )
    }
}

nonisolated struct TaskRecurrenceOccurrenceSnapshot:
    Equatable,
    Sendable
{
    let id: UUID
    let templateTaskID: UUID
    let dayKey: String
    let timeZoneIdentifier: String
    let localDate: Date

    @MainActor
    init?(occurrence: TaskRecurrenceOccurrence) {
        let expectedOccurrenceID = TaskProgressIdentity
            .recurrenceOccurrenceID(
                ruleID: occurrence.ruleID,
                dayKey: occurrence.occurrenceDayKey
            )
        let expectedGeneratedTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: occurrence.ruleID,
            dayKey: occurrence.occurrenceDayKey
        )
        guard occurrence.id == expectedOccurrenceID,
              occurrence.generatedTaskID == expectedGeneratedTaskID,
              let localDate = TaskRecurrenceDayKey.date(
                  from: occurrence.occurrenceDayKey,
                  timeZoneIdentifier: occurrence.timeZoneIdentifier
              ) else {
            return nil
        }
        id = occurrence.id
        templateTaskID = occurrence.templateTaskID
        dayKey = occurrence.occurrenceDayKey
        timeZoneIdentifier = occurrence.timeZoneIdentifier
        self.localDate = localDate
    }

    init(
        id: UUID,
        templateTaskID: UUID,
        dayKey: String,
        timeZoneIdentifier: String,
        localDate: Date
    ) {
        self.id = id
        self.templateTaskID = templateTaskID
        self.dayKey = dayKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localDate = localDate
    }

    func formattedDateText(
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            return dayKey
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return localDate.formatted(
            Date.FormatStyle(
                locale: locale,
                calendar: calendar,
                timeZone: timeZone
            )
            .year()
            .month(.abbreviated)
            .day()
        )
    }
}

nonisolated enum TaskQuantityRecurrenceRole: Equatable, Sendable {
    case ordinary
    case template
    case generated(TaskRecurrenceOccurrenceSnapshot)
}

nonisolated struct TaskQuantityDetailSnapshot: Equatable, Sendable {
    let progress: TaskQuantityProgressSnapshot
    let entries: [TaskQuantityEntrySnapshot]
    let recurrenceRole: TaskQuantityRecurrenceRole
}

nonisolated enum TaskQuantityDetailReadModel: Equatable, Sendable {
    case none
    case incomplete
    case available(TaskQuantityDetailSnapshot)
}
