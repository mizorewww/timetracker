import Foundation

/// The sendable part of the Analytics Today read model. SwiftData projection
/// happens before this value is created, so its worker never retains a
/// persistent model or `ModelContext`.
nonisolated struct AnalyticsVisualSnapshotInput: Sendable {
    let range: AnalyticsRange
    let period: DateInterval
    let evaluatedAt: Date
    let calendar: Calendar
    let segments: [AnalyticsVisualSegment]
    let taskByID: [UUID: AnalyticsVisualTask]
    let timelineFallbackTitleByTaskID: [UUID: String]
    let overlapFallbackTitleByTaskID: [UUID: String]
    let unavailableTaskTitle: String
    let unavailableTaskPath: String

    @MainActor
    init(
        range: AnalyticsRange,
        period: DateInterval,
        evaluatedAt: Date,
        calendar: Calendar,
        segments: [TimeSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        taskParentPathByID: [UUID: String]
    ) {
        self.range = range
        self.period = period
        self.evaluatedAt = evaluatedAt
        self.calendar = calendar
        self.segments = segments.deduplicatedByID().map(AnalyticsVisualSegment.init)
        taskByID = tasks.latestByID().reduce(into: [:]) { result, pair in
            result[pair.key] = AnalyticsVisualTask(
                title: pair.value.title,
                path: taskParentPathByID[pair.key] ?? AppStrings.rootTask,
                iconName: pair.value.iconName ?? "checkmark.circle",
                colorHex: pair.value.colorHex ?? "0A84FF"
            )
        }
        timelineFallbackTitleByTaskID = Dictionary(
            grouping: sessions.deduplicatedByID(),
            by: \.taskID
        ).compactMapValues { $0.first?.titleSnapshot }
        overlapFallbackTitleByTaskID = AnalyticsSelectionPolicy.latestSessionTitleByTaskID(
            sessions: sessions
        )
        unavailableTaskTitle = AppStrings.localized("task.unavailable")
        unavailableTaskPath = AppStrings.localized("task.unavailable.path")
    }
}

nonisolated struct AnalyticsVisualSegment: Sendable {
    let id: UUID
    let taskID: UUID
    let startedAt: Date
    let endedAt: Date?
    let deletedAt: Date?

    @MainActor
    init(_ segment: TimeSegment) {
        id = segment.id
        taskID = segment.taskID
        startedAt = segment.startedAt
        endedAt = segment.endedAt
        deletedAt = segment.deletedAt
    }
}

nonisolated struct AnalyticsVisualTask: Sendable {
    let title: String
    let path: String
    let iconName: String
    let colorHex: String
}

nonisolated struct AnalyticsVisualSnapshot: Equatable, Sendable {
    let todayActivity: [HourTaskActivity]
    let timeline: AnalyticsTimelineSnapshot
    let overlaps: [OverlapAnalyticsPoint]

    static let empty = AnalyticsVisualSnapshot(
        todayActivity: [],
        timeline: .empty,
        overlaps: []
    )
}

nonisolated enum AnalyticsVisualSnapshotTask {
    static func resolve(_ input: AnalyticsVisualSnapshotInput) async -> AnalyticsVisualSnapshot? {
        let task: Task<AnalyticsVisualSnapshot?, Never> = Task.detached(priority: .userInitiated) {
            guard Task.isCancelled == false else { return nil }
            return AnalyticsVisualSnapshotService().snapshot(input)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

nonisolated struct AnalyticsVisualBoundedSegment {
    let id: UUID
    let taskID: UUID
    let interval: DateInterval

    var durationSeconds: Int {
        max(0, Int(interval.end.timeIntervalSince(interval.start)))
    }
}
