import Foundation

/// Main-actor owned indexes that turn rollup mutation refreshes into work
/// proportional to changed records, hierarchy depth, and a bounded 90-day
/// forecast window. Full-history elapsed totals remain exact.
struct RollupIncrementalIndex {
    static let historicalPaceDayCount = TaskRollupHistoricalPolicy.paceDayCount

    private(set) var taskByID: [UUID: TaskNode] = [:]
    private(set) var childrenByParent: [UUID?: [TaskNode]] = [:]
    private(set) var postorderTaskIDs: [UUID] = []
    private(set) var ownWorkedSecondsByTaskID: [UUID: Int] = [:]
    private(set) var checklistProgressByTaskID: [UUID: ChecklistProgress] = [:]
    var historicalPaceByTaskID: [UUID: TaskRollupHistoricalPace] = [:]
    var activitySummaryByTaskID: [UUID: TaskLedgerActivitySummary] = [:]

    var parentByTaskID: [UUID: UUID] = [:]
    var depthByTaskID: [UUID: Int] = [:]
    var segmentByID: [UUID: LedgerSegmentSnapshot] = [:]
    var segmentIDsByTaskID: [UUID: Set<UUID>] = [:]
    var timeSensitiveSegmentIDs: Set<UUID> = []
    var ownRecentDaySecondsByTaskID: [UUID: [Date: Int]] = [:]
    var subtreeRecentDaySecondsByTaskID: [UUID: [Date: Int]] = [:]
    var taskIDsByRecentDay: [Date: Set<UUID>] = [:]
    var recentWindowStart = Date.distantPast
    var lastEvaluationDate = Date.distantPast
    var calendar = Calendar.current

    var isInitialized: Bool {
        lastEvaluationDate != .distantPast
    }

    mutating func adjustOwnWorkedSeconds(for taskID: UUID, by delta: Int) {
        ownWorkedSecondsByTaskID[taskID, default: 0] += delta
    }

    mutating func clampOwnWorkedSecondsToZero(for taskID: UUID) {
        ownWorkedSecondsByTaskID[taskID] = max(0, ownWorkedSecondsByTaskID[taskID] ?? 0)
    }

    mutating func replaceChecklistProgress(for taskID: UUID, items: [ChecklistItem]) {
        checklistProgressByTaskID[taskID] = progress(taskID: taskID, items: items)
    }

    mutating func rebuild(
        tasks: [TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        now: Date,
        calendar: Calendar = .current
    ) {
        let canonicalTasks = tasks.visibleDeduplicatedByID()
        taskByID = canonicalTasks.latestByID()
        childrenByParent = Dictionary(grouping: canonicalTasks, by: \.parentID)
        parentByTaskID = canonicalTasks.reduce(into: [:]) { result, task in
            if let parentID = task.parentID, taskByID[parentID] != nil {
                result[task.id] = parentID
            }
        }
        postorderTaskIDs = makePostorderTaskIDs(taskIDs: Set(taskByID.keys))
        depthByTaskID = makeDepths()

        var canonicalSegments: [LedgerSegmentSnapshot] = []
        canonicalSegments.reserveCapacity(segments.count)
        for segment in segments.visibleDeduplicatedByID() {
            canonicalSegments.append(LedgerSegmentSnapshot(segment))
        }
        segmentByID = Dictionary(uniqueKeysWithValues: canonicalSegments.map { ($0.id, $0) })
        segmentIDsByTaskID = Dictionary(grouping: canonicalSegments, by: \.taskID)
            .mapValues { Set($0.map(\.id)) }
        timeSensitiveSegmentIDs = Set(canonicalSegments.lazy.filter { $0.isTimeSensitive(at: now) }.map(\.id))
        rebuildActivitySummaries()
        ownWorkedSecondsByTaskID.removeAll(keepingCapacity: true)
        for segment in canonicalSegments {
            ownWorkedSecondsByTaskID[segment.taskID, default: 0] += segment.elapsedSeconds(at: now)
        }

        checklistProgressByTaskID = makeChecklistProgress(
            taskIDs: Set(taskByID.keys),
            checklistItems: checklistItems
        )

        self.calendar = calendar
        recentWindowStart = historicalWindowStart(now: now, calendar: calendar)
        lastEvaluationDate = now
        ownRecentDaySecondsByTaskID.removeAll(keepingCapacity: true)
        taskIDsByRecentDay.removeAll(keepingCapacity: true)
        for segment in canonicalSegments {
            mergeOwnDayDelta(
                taskID: segment.taskID,
                deltas: recentDaySeconds(for: segment, evaluatedAt: now)
            )
        }
        rebuildSubtreeRecentBuckets()
        rebuildHistoricalPaces(taskIDs: Set(taskByID.keys))
    }

}
