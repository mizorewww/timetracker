import Foundation

nonisolated struct ActivityHeatmapDateRange: Sendable {
    let interval: DateInterval
    let today: Date
}

nonisolated struct ActivityHeatmapTaskRecord: PersistentUUIDModel, Sendable {
    let id: UUID
    let parentID: UUID?
    let title: String
    let iconName: String?
    let colorHex: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let deviceID: String

    @MainActor
    init(_ task: TaskNode) {
        id = task.id
        parentID = task.parentID
        title = task.title
        iconName = task.iconName
        colorHex = task.colorHex
        createdAt = task.createdAt
        updatedAt = task.updatedAt
        deletedAt = task.deletedAt
        deviceID = task.deviceID
    }
}

nonisolated struct ActivityHeatmapSegmentRecord: PersistentUUIDModel, Sendable {
    let id: UUID
    let sessionID: UUID
    let taskID: UUID
    let startedAt: Date
    let endedAt: Date?
    let sourceRaw: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let deviceID: String

    @MainActor
    init(_ segment: TimeSegment) {
        id = segment.id
        sessionID = segment.sessionID
        taskID = segment.taskID
        startedAt = segment.startedAt
        endedAt = segment.endedAt
        sourceRaw = segment.sourceRaw
        createdAt = segment.createdAt
        updatedAt = segment.updatedAt
        deletedAt = segment.deletedAt
        deviceID = segment.deviceID
    }
}

nonisolated struct ActivityHeatmapChecklistRecord: PersistentUUIDModel, Sendable {
    let id: UUID
    let taskID: UUID
    let isCompleted: Bool
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let deviceID: String
    let clientMutationID: UUID

    @MainActor
    init(_ item: ChecklistItem) {
        id = item.id
        taskID = item.taskID
        isCompleted = item.isCompleted
        completedAt = item.completedAt
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        deletedAt = item.deletedAt
        deviceID = item.deviceID
        clientMutationID = item.clientMutationID
    }
}

nonisolated struct ActivityHeatmapQuantityGoalRecord: PersistentUUIDModel, Sendable {
    let id: UUID
    let taskID: UUID
    let targetAmount: Int
    let unitLabel: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let deviceID: String
    let clientMutationID: UUID

    @MainActor
    init(_ goal: TaskQuantityGoal) {
        id = goal.id
        taskID = goal.taskID
        targetAmount = goal.targetAmount
        unitLabel = goal.unitLabel
        createdAt = goal.createdAt
        updatedAt = goal.updatedAt
        deletedAt = goal.deletedAt
        deviceID = goal.deviceID
        clientMutationID = goal.clientMutationID
    }
}

nonisolated struct ActivityHeatmapQuantityEntryRecord: PersistentUUIDModel, Sendable {
    let id: UUID
    let taskID: UUID
    let quantityGoalID: UUID
    let amount: Int
    let recordedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let deviceID: String
    let clientMutationID: UUID

    @MainActor
    init(_ entry: TaskQuantityEntry) {
        id = entry.id
        taskID = entry.taskID
        quantityGoalID = entry.quantityGoalID
        amount = entry.amount
        recordedAt = entry.recordedAt
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
        deviceID = entry.deviceID
        clientMutationID = entry.clientMutationID
    }
}

nonisolated struct ActivityHeatmapSnapshotInput: Sendable {
    let selectedTaskIDs: [UUID]
    let taskByID: [UUID: ActivityHeatmapTaskRecord]
    let childIDsByParentID: [UUID?: [UUID]]
    let additionalContributingTaskIDsBySelectedTaskID: [UUID: Set<UUID>]
    let segments: [ActivityHeatmapSegmentRecord]
    let checklistItems: [ActivityHeatmapChecklistRecord]
    let quantityGoals: [ActivityHeatmapQuantityGoalRecord]
    let quantityEntries: [ActivityHeatmapQuantityEntryRecord]
    let period: ActivityHeatmapPeriod
    let now: Date
    let calendar: Calendar

    @MainActor
    init(
        selectedTaskIDs: [UUID],
        taskByID: [UUID: TaskNode],
        childrenByParentID: [UUID?: [TaskNode]],
        additionalContributingTaskIDsBySelectedTaskID: [UUID: Set<UUID>] = [:],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        quantityGoals: [TaskQuantityGoal],
        quantityEntries: [TaskQuantityEntry],
        period: ActivityHeatmapPeriod,
        now: Date,
        calendar: Calendar = .current
    ) {
        self.selectedTaskIDs = selectedTaskIDs
        self.taskByID = taskByID.mapValues(ActivityHeatmapTaskRecord.init)
        childIDsByParentID = childrenByParentID.mapValues { $0.map(\.id) }
        self.additionalContributingTaskIDsBySelectedTaskID =
            additionalContributingTaskIDsBySelectedTaskID
        self.segments = segments.map(ActivityHeatmapSegmentRecord.init)
        self.checklistItems = checklistItems.map(ActivityHeatmapChecklistRecord.init)
        self.quantityGoals = quantityGoals.map(ActivityHeatmapQuantityGoalRecord.init)
        self.quantityEntries = quantityEntries.map(ActivityHeatmapQuantityEntryRecord.init)
        self.period = period
        self.now = now
        self.calendar = calendar
    }
}

nonisolated struct ActivityHeatmapIndexes: Sendable {
    let segmentIntervalsByTaskID: [UUID: [DateInterval]]
    let checklistTaskIDs: Set<UUID>
    let checklistValuesByTaskAndDay: [UUID: [Date: Int]]
    let quantityGoalByTaskID: [UUID: ActivityHeatmapQuantityGoalRecord]
    let quantityValuesByTaskAndDay: [UUID: [Date: Int]]

    static let empty = ActivityHeatmapIndexes(
        segmentIntervalsByTaskID: [:],
        checklistTaskIDs: [],
        checklistValuesByTaskAndDay: [:],
        quantityGoalByTaskID: [:],
        quantityValuesByTaskAndDay: [:]
    )
}

nonisolated struct ActivityHeatmapValues: Sendable {
    let metric: ActivityHeatmapMetric
    let valuesByDay: [Date: Int]
    let referencesByDay: [Date: Int]
}

nonisolated func normalizedHeatmapUnit(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}
