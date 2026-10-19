import Foundation

/// Value copies of the SwiftData rows analytics reads. They are captured on
/// the main actor, already deduplicated with the models' last-write-wins
/// order, so the aggregation can run off the main actor without touching a
/// persistent model.
nonisolated struct AnalyticsSegmentRecord: PersistentUUIDModel, Sendable {
    let id: UUID
    let sessionID: UUID
    let taskID: UUID
    let startedAt: Date
    let endedAt: Date?
    let source: TimeSessionSource
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
        source = segment.source
        createdAt = segment.createdAt
        updatedAt = segment.updatedAt
        deletedAt = segment.deletedAt
        deviceID = segment.deviceID
    }

    @MainActor
    static func records(_ segments: [TimeSegment]) -> [AnalyticsSegmentRecord] {
        segments.deduplicatedByID().map(AnalyticsSegmentRecord.init)
    }
}

nonisolated struct AnalyticsTaskRecord: PersistentUUIDModel, Sendable {
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

    @MainActor
    static func records(_ tasks: [TaskNode]) -> [AnalyticsTaskRecord] {
        tasks.deduplicatedByID().map(AnalyticsTaskRecord.init)
    }
}

nonisolated struct AnalyticsSessionRecord: PersistentUUIDModel, Sendable {
    let id: UUID
    let taskID: UUID
    let titleSnapshot: String?
    let startedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let deviceID: String

    @MainActor
    init(_ session: TimeSession) {
        id = session.id
        taskID = session.taskID
        titleSnapshot = session.titleSnapshot
        startedAt = session.startedAt
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        deletedAt = session.deletedAt
        deviceID = session.deviceID
    }

    @MainActor
    static func records(_ sessions: [TimeSession]) -> [AnalyticsSessionRecord] {
        sessions.deduplicatedByID().map(AnalyticsSessionRecord.init)
    }
}

nonisolated struct AnalyticsCategoryRecord: PersistentUUIDModel, Sendable {
    let id: UUID
    let title: String
    let iconName: String?
    let colorHex: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let deviceID: String

    @MainActor
    init(_ category: TaskCategory) {
        id = category.id
        title = category.title
        iconName = category.iconName
        colorHex = category.colorHex
        createdAt = category.createdAt
        updatedAt = category.updatedAt
        deletedAt = category.deletedAt
        deviceID = category.deviceID
    }
}

/// Everything one analytics period snapshot is computed from.
nonisolated struct AnalyticsSnapshotInput: Sendable {
    let range: AnalyticsRange
    let period: DateInterval
    let evaluatedAt: Date
    let calendar: Calendar
    let tasks: [AnalyticsTaskRecord]
    let taskCategories: [AnalyticsCategoryRecord]
    /// Visible category of each root task, from the assignments' logical winners.
    let categoryIDByRootTaskID: [UUID: UUID]
    let segments: [AnalyticsSegmentRecord]
    let sessions: [AnalyticsSessionRecord]
    let cancelledPomodoroSessionIDs: Set<UUID>
    let taskPathByID: [UUID: String]
    let taskParentPathByID: [UUID: String]

    @MainActor
    init(
        range: AnalyticsRange,
        period: DateInterval,
        evaluatedAt: Date,
        calendar: Calendar,
        tasks: [TaskNode],
        taskCategories: [TaskCategory],
        taskCategoryAssignments: [TaskCategoryAssignment],
        segments: [TimeSegment],
        sessions: [TimeSession],
        cancelledPomodoroSessionIDs: Set<UUID>,
        taskPathByID: [UUID: String],
        taskParentPathByID: [UUID: String]
    ) {
        self.range = range
        self.period = period
        self.evaluatedAt = evaluatedAt
        self.calendar = calendar
        self.tasks = AnalyticsTaskRecord.records(tasks)
        self.taskCategories = taskCategories.deduplicatedByID().map(AnalyticsCategoryRecord.init)
        categoryIDByRootTaskID = taskCategoryAssignments
            .deduplicatedByID()
            .logicalWinnersByTaskID()
            .compactMapValues { $0.deletedAt == nil ? $0.categoryID : nil }
        self.segments = AnalyticsSegmentRecord.records(segments)
        self.sessions = AnalyticsSessionRecord.records(sessions)
        self.cancelledPomodoroSessionIDs = cancelledPomodoroSessionIDs
        self.taskPathByID = taskPathByID
        self.taskParentPathByID = taskParentPathByID
    }
}
