import Foundation

extension RollupIncrementalIndex {
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
                adjustOwnWorkedSeconds(
                    for: before.taskID,
                    by: -before.elapsedSeconds(at: lastEvaluationDate)
                )
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
                adjustOwnWorkedSeconds(for: after.taskID, by: after.elapsedSeconds(at: now))
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
            clampOwnWorkedSecondsToZero(for: taskID)
            rebuildActivitySummary(for: taskID)
        }
        for (taskID, deltas) in ownDayDeltasByTaskID {
            applyOwnDayDeltas(taskID: taskID, deltas: deltas)
        }

        for (taskID, items) in checklistItemsByTaskID where taskByID[taskID] != nil {
            replaceChecklistProgress(for: taskID, items: items)
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
            if leftDepth != rightDepth {
                return leftDepth > rightDepth
            }
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
