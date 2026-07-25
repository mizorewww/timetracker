import Foundation

struct TaskRollupHistoricalPace: Equatable {
    let averageSeconds: Int
    let activeDayCount: Int
}

struct TaskRollupRawInputs {
    let taskByID: [UUID: TaskNode]
    let childrenByParent: [UUID?: [TaskNode]]
    let ownWorkedSecondsByTaskID: [UUID: Int]
    let checklistProgressByTaskID: [UUID: ChecklistProgress]
    let historicalPaceByTaskID: [UUID: TaskRollupHistoricalPace]
    let postorderTaskIDs: [UUID]
}

struct TaskRollupInputAggregation {
    private struct DailyAccumulator {
        var totals: [Date: Int]
        var totalSeconds: Int
        var activeDayCount: Int

        init(totals: [Date: Int]) {
            self.totals = totals
            totalSeconds = totals.values.reduce(0, +)
            activeDayCount = totals.values.lazy.filter { $0 > 0 }.count
        }

        mutating func merge(_ other: DailyAccumulator) {
            totalSeconds += other.totalSeconds
            for (day, seconds) in other.totals {
                if totals[day] == nil, seconds > 0 {
                    activeDayCount += 1
                }
                totals[day, default: 0] += seconds
            }
        }
    }

    func inputs(
        tasks: [TaskNode],
        segments: [TimeSegment],
        checklistItems: [ChecklistItem],
        now: Date
    ) -> TaskRollupRawInputs {
        let canonicalTasks = tasks.deduplicatedByID()
        let taskByID = canonicalTasks.latestByID()
        let childrenByParent = Dictionary(grouping: canonicalTasks, by: \.parentID)
        let segmentsByTaskID = Dictionary(
            grouping: segments.deduplicatedByID().filter { $0.deletedAt == nil },
            by: \.taskID
        )
        let postorderTaskIDs = makePostorderTaskIDs(
            taskIDs: Set(taskByID.keys),
            childrenByParent: childrenByParent
        )
        let checklistItemsByTaskID = Dictionary(
            grouping: checklistItems.deduplicatedByID().filter { $0.deletedAt == nil },
            by: \.taskID
        )
        let checklistProgressByTaskID = checklistItemsByTaskID.reduce(
            into: [UUID: ChecklistProgress]()
        ) { result, entry in
            result[entry.key] = ChecklistProgress(
                taskID: entry.key,
                totalCount: entry.value.count,
                completedCount: entry.value.lazy.filter(\.isCompleted).count
            )
        }
        let aggregation = TimeAggregationService()
        return TaskRollupRawInputs(
            taskByID: taskByID,
            childrenByParent: childrenByParent,
            ownWorkedSecondsByTaskID: segmentsByTaskID.mapValues {
                aggregation.grossSeconds($0, now: now)
            },
            checklistProgressByTaskID: checklistProgressByTaskID,
            historicalPaceByTaskID: makeHistoricalPaces(
                postorderTaskIDs: postorderTaskIDs,
                childrenByParent: childrenByParent,
                segmentsByTaskID: segmentsByTaskID,
                now: now
            ),
            postorderTaskIDs: postorderTaskIDs
        )
    }

    /// Child-before-parent order that is also safe for malformed staged imports.
    private func makePostorderTaskIDs(
        taskIDs: Set<UUID>,
        childrenByParent: [UUID?: [TaskNode]]
    ) -> [UUID] {
        var stateByID: [UUID: UInt8] = [:]
        var result: [UUID] = []
        for startID in taskIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard stateByID[startID] == nil else { continue }
            var stack: [(id: UUID, expanded: Bool)] = [(startID, false)]
            while let entry = stack.popLast() {
                if entry.expanded {
                    guard stateByID[entry.id] != 2 else { continue }
                    stateByID[entry.id] = 2
                    result.append(entry.id)
                    continue
                }
                guard stateByID[entry.id] == nil else { continue }
                stateByID[entry.id] = 1
                stack.append((entry.id, true))
                let children = (childrenByParent[entry.id] ?? [])
                    .map(\.id)
                    .filter { taskIDs.contains($0) && stateByID[$0] == nil }
                    .sorted { $0.uuidString > $1.uuidString }
                stack.append(contentsOf: children.map { ($0, false) })
            }
        }
        return result
    }

    /// Uses the same bounded recent window as the application's incremental
    /// index so service callers cannot trigger a full-history day-by-day scan.
    private func makeHistoricalPaces(
        postorderTaskIDs: [UUID],
        childrenByParent: [UUID?: [TaskNode]],
        segmentsByTaskID: [UUID: [TimeSegment]],
        now: Date,
        calendar: Calendar = .current
    ) -> [UUID: TaskRollupHistoricalPace] {
        var accumulatorsByTaskID = segmentsByTaskID.mapValues {
            DailyAccumulator(totals: dailyTotals(segments: $0, now: now, calendar: calendar))
        }
        var result: [UUID: TaskRollupHistoricalPace] = [:]
        for taskID in postorderTaskIDs {
            let contributorIDs = [taskID] + (childrenByParent[taskID] ?? []).map(\.id)
            let baseID = contributorIDs.max { lhs, rhs in
                (accumulatorsByTaskID[lhs]?.totals.count ?? 0) <
                    (accumulatorsByTaskID[rhs]?.totals.count ?? 0)
            }
            var accumulator = baseID.flatMap { accumulatorsByTaskID.removeValue(forKey: $0) } ??
                DailyAccumulator(totals: [:])
            for contributorID in contributorIDs where contributorID != baseID {
                guard let contribution = accumulatorsByTaskID.removeValue(forKey: contributorID) else { continue }
                accumulator.merge(contribution)
            }
            if accumulator.activeDayCount > 0 {
                result[taskID] = TaskRollupHistoricalPace(
                    averageSeconds: accumulator.totalSeconds / accumulator.activeDayCount,
                    activeDayCount: accumulator.activeDayCount
                )
            }
            accumulatorsByTaskID[taskID] = accumulator
        }
        return result
    }

    private func dailyTotals(
        segments: [TimeSegment],
        now: Date,
        calendar: Calendar
    ) -> [Date: Int] {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(
            byAdding: .day,
            value: -(TaskRollupHistoricalPolicy.paceDayCount - 1),
            to: today
        ) ?? today.addingTimeInterval(
            -Double(TaskRollupHistoricalPolicy.paceDayCount - 1) * 86400
        )
        let intervals = segments.compactMap { segment -> DateInterval? in
            TrackedTimePolicy.interval(
                startedAt: segment.startedAt,
                endedAt: segment.endedAt,
                now: now,
                clippedTo: DateInterval(start: windowStart, end: now)
            )
        }
        return TimeAggregationService().secondsByDay(intervals: intervals, calendar: calendar)
    }
}
