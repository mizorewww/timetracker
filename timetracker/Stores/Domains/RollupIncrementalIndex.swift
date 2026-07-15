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

    mutating func apply(
        directTaskIDs: Set<UUID>,
        explicitAncestorTaskIDs: Set<UUID>,
        segmentChanges: [LedgerSegmentChange],
        checklistItemsByTaskID: [UUID: [ChecklistItem]],
        now: Date,
        calendar: Calendar = .current
    ) -> [UUID] {
        guard isInitialized else { return [] }

        var ownDayDeltasByTaskID: [UUID: [Date: Int]] = [:]
        let calendarChanged = self.calendar != calendar
        let rebuiltAllPaceBuckets: Bool
        if calendarChanged {
            // Calendar/time-zone changes alter every day boundary. They are
            // rare, so rebuild the bounded buckets from immutable snapshots
            // and invalidate every rollup instead of mixing incompatible keys.
            self.calendar = calendar
            rebuildRecentBuckets(
                evaluatedAt: lastEvaluationDate,
                windowStart: historicalWindowStart(now: now, calendar: calendar)
            )
            rebuiltAllPaceBuckets = true
        } else {
            rebuiltAllPaceBuckets = advanceHistoricalWindow(
                to: historicalWindowStart(now: now, calendar: calendar),
                ownDayDeltasByTaskID: &ownDayDeltasByTaskID
            )
        }

        // Coalesce defensively because multiple domain events may describe the
        // same segment before the refresh planner flushes its pending work.
        let suppliedChanges = segmentChanges.reduce(into: [UUID: LedgerSegmentChange]()) {
            result, change in
            if let pending = result[change.id] {
                result[change.id] = LedgerSegmentChange(
                    id: change.id,
                    before: pending.before,
                    after: change.after
                )
            } else {
                result[change.id] = change
            }
        }
        // A backward wall-clock correction can move any previously completed
        // record back across the reference boundary. Re-evaluate all records in
        // that rare case; forward refreshes remain proportional to active or
        // future-ended records plus explicit mutations.
        let advancingTimeSensitiveIDs = now < lastEvaluationDate
            ? Set(segmentByID.keys)
            : timeSensitiveSegmentIDs
        let timeSensitiveIDs = advancingTimeSensitiveIDs.union(suppliedChanges.keys)
        var timeAffectedTaskIDs = Set<UUID>()

        for segmentID in timeSensitiveIDs {
            let before = segmentByID[segmentID]
            let after = suppliedChanges[segmentID]?.after ?? before
            if let before {
                timeAffectedTaskIDs.insert(before.taskID)
                ownWorkedSecondsByTaskID[before.taskID, default: 0] -= before.elapsedSeconds(at: lastEvaluationDate)
                mergeDayDeltas(
                    recentDaySeconds(for: before, evaluatedAt: lastEvaluationDate),
                    into: &ownDayDeltasByTaskID[before.taskID, default: [:]],
                    multiplier: -1
                )
                segmentIDsByTaskID[before.taskID]?.remove(segmentID)
                if segmentIDsByTaskID[before.taskID]?.isEmpty == true {
                    segmentIDsByTaskID.removeValue(forKey: before.taskID)
                }
            }

            if let after {
                timeAffectedTaskIDs.insert(after.taskID)
                ownWorkedSecondsByTaskID[after.taskID, default: 0] += after.elapsedSeconds(at: now)
                mergeDayDeltas(
                    recentDaySeconds(for: after, evaluatedAt: now),
                    into: &ownDayDeltasByTaskID[after.taskID, default: [:]],
                    multiplier: 1
                )
                segmentByID[segmentID] = after
                segmentIDsByTaskID[after.taskID, default: []].insert(segmentID)
                if after.isTimeSensitive(at: now) {
                    timeSensitiveSegmentIDs.insert(segmentID)
                } else {
                    timeSensitiveSegmentIDs.remove(segmentID)
                }
            } else {
                segmentByID.removeValue(forKey: segmentID)
                timeSensitiveSegmentIDs.remove(segmentID)
            }
        }

        for taskID in timeAffectedTaskIDs {
            ownWorkedSecondsByTaskID[taskID] = max(0, ownWorkedSecondsByTaskID[taskID] ?? 0)
            rebuildActivitySummary(for: taskID)
        }
        for (taskID, deltas) in ownDayDeltasByTaskID {
            applyOwnDayDeltas(taskID: taskID, deltas: deltas)
        }

        for (taskID, items) in checklistItemsByTaskID where taskByID[taskID] != nil {
            checklistProgressByTaskID[taskID] = progress(taskID: taskID, items: items)
        }

        lastEvaluationDate = now
        self.calendar = calendar

        var directlyAffected = Set(directTaskIDs
            .union(checklistItemsByTaskID.keys)
            .union(timeAffectedTaskIDs)
            // Advancing the 90-day window can expire a bucket belonging to a
            // task unrelated to the command that happened to trigger refresh.
            .union(ownDayDeltasByTaskID.keys)
            .filter { taskByID[$0] != nil })
        if rebuiltAllPaceBuckets {
            directlyAffected = Set(taskByID.keys)
        }
        var allAffected = directlyAffected.union(
            explicitAncestorTaskIDs.filter { taskByID[$0] != nil }
        )
        for taskID in directlyAffected {
            allAffected.formUnion(ancestorIDs(of: taskID))
        }
        rebuildHistoricalPaces(taskIDs: allAffected)
        return allAffected.sorted { lhs, rhs in
            let leftDepth = depthByTaskID[lhs] ?? 0
            let rightDepth = depthByTaskID[rhs] ?? 0
            if leftDepth != rightDepth { return leftDepth > rightDepth }
            return lhs.uuidString < rhs.uuidString
        }
    }

    func replacementChanges(
        taskIDs: Set<UUID>,
        segments: [TimeSegment]
    ) -> [LedgerSegmentChange] {
        var refreshed: [LedgerSegmentSnapshot] = []
        for segment in segments.visibleDeduplicatedByID() where taskIDs.contains(segment.taskID) {
            refreshed.append(LedgerSegmentSnapshot(segment))
        }
        let refreshedByID = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, $0) })
        let existingIDs = taskIDs.reduce(into: Set<UUID>()) { result, taskID in
            result.formUnion(segmentIDsByTaskID[taskID] ?? [])
        }
        return existingIDs.union(refreshedByID.keys).map { id in
            LedgerSegmentChange(id: id, before: segmentByID[id], after: refreshedByID[id])
        }
    }

}
