import Foundation
import SwiftData

nonisolated enum CommittedMutationSystemSurfaceMaterializationCheckpoint:
    Equatable,
    Sendable
{
    case beforeCommittedFactRead
    case afterCommittedFactRead
    case afterMaterialization
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
    typealias Checkpoint = @Sendable (
        CommittedMutationSystemSurfaceMaterializationCheckpoint
    ) -> Void

    func materialize(
        now: Date = Date(),
        calendar: Calendar = .current,
        didReachCheckpoint: Checkpoint = { _ in }
    ) throws -> CommittedMutationSystemProjectionMaterialization {
        didReachCheckpoint(.beforeCommittedFactRead)

        let canonicalTaskRows = try modelContext
            .fetch(FetchDescriptor<TaskNode>())
            .deduplicatedByID()
        let tasks = canonicalTaskRows
            .filter { $0.deletedAt == nil }
            .sorted(by: taskHierarchyOrder)
        let fetchedRecurrenceRules = try modelContext
            .fetch(FetchDescriptor<TaskRecurrenceRule>())
            .visibleDeduplicatedByID()
        let fetchedRecurrenceOccurrences = try modelContext
            .fetch(FetchDescriptor<TaskRecurrenceOccurrence>())
            .visibleDeduplicatedByID()
        let recurrence = completeRecurrenceFacts(
            tasks: tasks,
            rules: fetchedRecurrenceRules,
            occurrences: fetchedRecurrenceOccurrences
        )
        let sessions = try modelContext
            .fetch(FetchDescriptor<TimeSession>())
            .visibleDeduplicatedByID()
        let segments = try modelContext
            .fetch(FetchDescriptor<TimeSegment>())
            .visibleDeduplicatedByID()
        let preferences = try modelContext
            .fetch(FetchDescriptor<SyncedPreference>())
            .deduplicatedByID()

        let readableSegments = readableSegments(
            canonicalTaskRows: canonicalTaskRows,
            sessions: sessions,
            segments: segments
        )
        didReachCheckpoint(.afterCommittedFactRead)

        let tree = TaskTreeService().indexes(tasks: tasks)
        let trackableTaskIDs = TaskTrackingAvailabilityService()
            .directWorkTaskIDs(
                tasks: tasks,
                recurrenceRules: recurrence.rules,
                recurrenceOccurrences: recurrence.occurrences
            )
            .subtracting(recurrence.incompleteTaskIDs)
        let activityByTaskID = taskActivityByTaskID(
            segments: readableSegments
        )
        let availableTasks = tasks.filter {
            trackableTaskIDs.contains($0.id)
        }
        let rankingService = TaskUsageRankingService()
        let rankedTasks = rankingService.rankedTasks(
            availableTasks: availableTasks,
            activityByTaskID: activityByTaskID
        )
        let activeSegments = readableSegments
            .filter { $0.endedAt == nil }
            .sorted(by: segmentStartOrder)
        let activeTaskIDs = Set(activeSegments.map(\.taskID))
        let recentTasks = rankingService.frequentRecentTasks(
            availableTasks: availableTasks,
            rankedTasks: rankedTasks,
            activityByTaskID: activityByTaskID,
            excluding: activeTaskIDs,
            limit: 3
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
        let liveActivity = liveActivityProjection(
            activeSegments: activeSegments,
            tree: tree,
            now: now
        )
        let materialization =
            CommittedMutationSystemProjectionMaterialization(
                widgetSnapshot: widgetSnapshot,
                watchSnapshot: watchSnapshot,
                liveActivity: liveActivity,
                generatedAt: now
            )
        didReachCheckpoint(.afterMaterialization)
        return materialization
    }

    private func completeRecurrenceFacts(
        tasks: [TaskNode],
        rules: [TaskRecurrenceRule],
        occurrences: [TaskRecurrenceOccurrence]
    ) -> (
        rules: [TaskRecurrenceRule],
        occurrences: [TaskRecurrenceOccurrence],
        incompleteTaskIDs: Set<UUID>
    ) {
        let taskIDs = Set(tasks.map(\.id))
        let visibleRuleByID = rules.latestByID()
        var incompleteTaskIDs = Set<UUID>()

        for occurrence in occurrences {
            let relationshipIsComplete =
                visibleRuleByID[occurrence.ruleID]?.templateTaskID ==
                occurrence.templateTaskID &&
                taskIDs.contains(occurrence.templateTaskID) &&
                taskIDs.contains(occurrence.generatedTaskID)
            guard relationshipIsComplete == false else { continue }
            if taskIDs.contains(occurrence.templateTaskID) {
                incompleteTaskIDs.insert(occurrence.templateTaskID)
            }
            if taskIDs.contains(occurrence.generatedTaskID) {
                incompleteTaskIDs.insert(occurrence.generatedTaskID)
            }
        }

        let completeRules = rules.filter {
            taskIDs.contains($0.templateTaskID)
        }
        let completeRuleByID = completeRules.latestByID()
        let completeOccurrences = occurrences.filter {
            completeRuleByID[$0.ruleID]?.templateTaskID ==
                $0.templateTaskID &&
                taskIDs.contains($0.templateTaskID) &&
                taskIDs.contains($0.generatedTaskID)
        }
        return (
            completeRules,
            completeOccurrences,
            incompleteTaskIDs
        )
    }

    private func readableSegments(
        canonicalTaskRows: [TaskNode],
        sessions: [TimeSession],
        segments: [TimeSegment]
    ) -> [TimeSegment] {
        let existingTaskIDs = Set(canonicalTaskRows.map(\.id))
        var taskIDBySessionID: [UUID: UUID] = [:]
        for session in sessions
            where existingTaskIDs.contains(session.taskID)
        {
            taskIDBySessionID[session.id] = session.taskID
        }
        return segments
            .filter {
                existingTaskIDs.contains($0.taskID) &&
                    taskIDBySessionID[$0.sessionID] == $0.taskID
            }
            .sorted(by: segmentStartOrder)
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
        let summary = LedgerSummaryService()
        return (
            summary.secondsInInterval(
                taskIDs: taskIDs,
                segments: visibleSegments,
                interval: interval,
                mode: .gross,
                now: now
            ),
            summary.secondsInInterval(
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
                WatchTransportLimits.maximumQuickStartTasks
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
        let legacyOrderedTasks =
            TaskUsageRankingService().legacyWatchTaskOrder(
                availableTasks: availableTasks,
                rankedTasks: rankedTasks,
                activityByTaskID: activityByTaskID,
                quickStartTaskIDs: quickStartTaskIDs,
                taskPathByID: tree.taskPathByID
            )
        return WatchStateProjectionService().snapshot(
            widgetSnapshot: widgetSnapshot,
            rankedTasks: rankedTasks,
            legacyOrderedTasks: legacyOrderedTasks,
            taskParentPathByID: tree.taskParentPathByID,
            quickStartTaskIDs: quickStartTaskIDs
        )
    }

    private func liveActivityProjection(
        activeSegments: [TimeSegment],
        tree: TaskTreeIndexes,
        now: Date
    ) -> CommittedMutationLiveActivityProjection {
        let service = LiveActivityProjectionService()
        guard let primary = service.primarySegment(
            from: activeSegments,
            now: now
        ) else {
            return .inactive
        }
        let task = service.taskProjection(
            taskID: primary.taskID,
            indexes: tree,
            fallbackTitle: AppStrings.localized("home.activeTimers")
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

    private func taskHierarchyOrder(
        _ lhs: TaskNode,
        _ rhs: TaskNode
    ) -> Bool {
        if lhs.depth != rhs.depth {
            return lhs.depth < rhs.depth
        }
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func segmentStartOrder(
        _ lhs: TimeSegment,
        _ rhs: TimeSegment
    ) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
