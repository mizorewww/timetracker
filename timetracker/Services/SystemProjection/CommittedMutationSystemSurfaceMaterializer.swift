import Foundation
import SwiftData

nonisolated struct CommittedMutationLiveActivityState:
    Equatable,
    Sendable
{
    let segmentID: String
    let taskID: String
    let taskTitle: String
    let taskPath: String
    let taskPathAbbreviated: String
    let iconName: String
    let colorHex: String
    let startedAt: Date
}

nonisolated enum CommittedMutationLiveActivityProjection:
    Equatable,
    Sendable
{
    case inactive
    case active(CommittedMutationLiveActivityState)

    static func materialize(
        activeSegments: [TimeSegment],
        indexes: TaskTreeIndexes,
        now: Date
    ) -> Self {
        let projectionService = LiveActivityProjectionService()
        guard let primary = projectionService.primarySegment(
            from: activeSegments,
            now: now
        ) else {
            return .inactive
        }
        let task = projectionService.taskProjection(
            taskID: primary.taskID,
            indexes: indexes,
            fallbackTitle: AppStrings.activeTimers
        )
        return .active(CommittedMutationLiveActivityState(
            segmentID: primary.id.uuidString,
            taskID: primary.taskID.uuidString,
            taskTitle: task.title,
            taskPath: task.path,
            taskPathAbbreviated: task.abbreviatedPath,
            iconName: task.iconName,
            colorHex: task.colorHex,
            startedAt: primary.startedAt
        ))
    }
}

/// One value snapshot of the committed store for every external system
/// surface. Retaining a failed generation never retains its ModelContext.
nonisolated struct CommittedMutationSystemProjectionMaterialization:
    Sendable
{
    let widgetSnapshot: WidgetSnapshot
    let watchSnapshot: WatchStateSnapshot
    let liveActivity: CommittedMutationLiveActivityProjection
    let generatedAt: Date
}

/// Reads one fresh generation of committed SwiftData facts on its dedicated
/// model executor, then materializes the immutable Widget, Watch, and Live
/// Activity values on that same executor.
///
/// The actor deliberately retains neither its input models nor its output DTO.
/// A caller can therefore replace it together with a `ModelContainer` without
/// allowing a cached generation to cross container boundaries.
@ModelActor
actor CommittedMutationSystemSurfaceMaterializer {
    /// Usage ranking for compact surfaces considers this many recent days.
    static let activityWindowDays = 90

    func materialize(
        now: Date = Date(),
        calendar: Calendar = .current
    ) throws -> CommittedMutationSystemProjectionMaterialization {
        let catalog = try TrackableTaskCatalog(context: modelContext)
        let segments = try activitySegments(now: now, calendar: calendar)
        let sessionIDs = Array(Set(segments.map(\.sessionID)))
        let sessions = try modelContext
            .fetch(FetchDescriptor<TimeSession>(
                predicate: #Predicate { sessionIDs.contains($0.id) }
            ))
            .visibleDeduplicatedByID()
        let preferences = try modelContext
            .fetch(FetchDescriptor<SyncedPreference>())
            .deduplicatedByID()

        let readableSegments = catalog.readableSegments(segments, sessions: sessions)

        let tree = catalog.tree
        let activityByTaskID = taskActivityByTaskID(
            segments: readableSegments
        )
        let availableTasks = catalog.trackableTasks
        let rankedTasks = TaskUsageRankingService.rankedTasks(
            availableTasks: availableTasks,
            activityByTaskID: activityByTaskID
        )
        let activeSegments = readableSegments
            .filter { $0.endedAt == nil }
        let activeTaskIDs = Set(activeSegments.map(\.taskID))
        let recentTasks = TaskUsageRankingService.frequentRecentTasks(
            availableTasks: availableTasks,
            rankedTasks: rankedTasks,
            activityByTaskID: activityByTaskID,
            excluding: activeTaskIDs,
            limit: SystemSurfaceLimits.maximumWidgetRecentTasks
        )
        let totals = todayTotals(
            segments: readableSegments,
            now: now,
            calendar: calendar
        )
        let widgetSnapshot = WidgetSnapshotProjection.snapshot(
            activeSegments: activeSegments,
            taskByID: tree.taskByID,
            taskParentPathByID: tree.taskParentPathByID,
            recentTasks: recentTasks,
            todayGrossSeconds: totals.gross,
            todayWallSeconds: totals.wall,
            generatedAt: now
        )
        let quickStartTaskIDs = quickStartTaskIDs(
            preferences: preferences
        )
        let watchSnapshot = watchSnapshot(
            availableTasks: availableTasks,
            rankedTasks: rankedTasks,
            activityByTaskID: activityByTaskID,
            tree: tree,
            quickStartTaskIDs: quickStartTaskIDs,
            widgetSnapshot: widgetSnapshot
        )
        let liveActivity = CommittedMutationLiveActivityProjection.materialize(
            activeSegments: activeSegments,
            indexes: tree,
            now: now
        )
        return CommittedMutationSystemProjectionMaterialization(
            widgetSnapshot: widgetSnapshot,
            watchSnapshot: watchSnapshot,
            liveActivity: liveActivity,
            generatedAt: now
        )
    }

    /// Running segments plus every segment that ended inside the activity
    /// window. The window covers today's totals and bounds usage ranking, so a
    /// timer start or stop never reads the whole ledger history.
    private func activitySegments(
        now: Date,
        calendar: Calendar
    ) throws -> [TimeSegment] {
        let windowStart = calendar.date(
            byAdding: .day,
            value: -Self.activityWindowDays,
            to: calendar.startOfDay(for: now)
        ) ?? now
        let candidateIDs = try Array(Set(modelContext
                .fetch(FetchDescriptor<TimeSegment>(
                    predicate: #Predicate {
                        ($0.endedAt ?? now) > windowStart
                    }
                ))
                .map(\.id)))
        // Re-read by ID so last-writer-wins sees every duplicate row of a
        // candidate before tombstones are filtered.
        return try modelContext
            .fetch(FetchDescriptor<TimeSegment>(
                predicate: #Predicate { candidateIDs.contains($0.id) }
            ))
            .visibleDeduplicatedByID()
    }

    private func taskActivityByTaskID(
        segments: [TimeSegment]
    ) -> [UUID: TaskLedgerActivitySummary] {
        segments.reduce(into: [:]) { activityByTaskID, segment in
            let activity = activityByTaskID[segment.taskID]
            activityByTaskID[segment.taskID] =
                TaskLedgerActivitySummary(
                    segmentCount:
                    (activity?.segmentCount ?? 0) + 1,
                    lastStartedAt: max(
                        activity?.lastStartedAt ?? .distantPast,
                        segment.startedAt
                    )
                )
        }
    }

    private func todayTotals(
        segments: [TimeSegment],
        now: Date,
        calendar: Calendar
    ) -> (gross: Int, wall: Int) {
        guard let interval = calendar.dateInterval(
            of: .day,
            for: now
        ) else {
            return (0, 0)
        }
        let visibleSegments = segments.filter {
            TrackedTimePolicy.overlaps(
                startedAt: $0.startedAt,
                endedAt: $0.endedAt,
                interval: interval,
                now: now
            )
        }
        let taskIDs = Set(visibleSegments.map(\.taskID))
        return (
            LedgerSummaryService.secondsInInterval(
                taskIDs: taskIDs,
                segments: visibleSegments,
                interval: interval,
                mode: .gross,
                now: now
            ),
            LedgerSummaryService.secondsInInterval(
                taskIDs: taskIDs,
                segments: visibleSegments,
                interval: interval,
                mode: .wallClock,
                now: now
            )
        )
    }

    private func quickStartTaskIDs(
        preferences: [SyncedPreference]
    ) -> [UUID] {
        guard let preference = SyncedPreferenceService
            .latestByKey(preferences)[
                AppPreferenceKey.quickStartTaskIDs.rawValue
            ],
            preference.deletedAt == nil,
            let data = preference.valueJSON.data(using: .utf8),
            let values = try? JSONDecoder().decode(
                [String].self,
                from: data
            )
        else {
            return []
        }

        var seen = Set<UUID>()
        var result: [UUID] = []
        for value in values {
            guard let taskID = UUID(uuidString: value),
                  seen.insert(taskID).inserted
            else {
                continue
            }
            result.append(taskID)
            if result.count ==
                SystemSurfaceLimits.maximumQuickStartTasks
            {
                break
            }
        }
        return result
    }

    private func watchSnapshot(
        availableTasks: [TaskNode],
        rankedTasks: [TaskNode],
        activityByTaskID: [UUID: TaskLedgerActivitySummary],
        tree: TaskTreeIndexes,
        quickStartTaskIDs: [UUID],
        widgetSnapshot: WidgetSnapshot
    ) -> WatchStateSnapshot {
        let availableTaskByID = Dictionary(
            availableTasks.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let pinnedTasks = quickStartTaskIDs.compactMap {
            availableTaskByID[$0]
        }
        let fillTasks = TaskUsageRankingService.frequentRecentTasks(
            availableTasks: availableTasks,
            rankedTasks: rankedTasks,
            activityByTaskID: activityByTaskID,
            excluding: Set(pinnedTasks.map(\.id)),
            limit: SystemSurfaceLimits.maximumQuickStartTasks - pinnedTasks.count
        )
        return WatchStateProjectionService().snapshot(
            widgetSnapshot: widgetSnapshot,
            rankedTasks: rankedTasks,
            quickStartTasks: pinnedTasks + fillTasks,
            taskParentPathByID: tree.taskParentPathByID
        )
    }
}
