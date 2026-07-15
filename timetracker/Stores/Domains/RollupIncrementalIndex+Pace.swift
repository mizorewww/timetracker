import Foundation

extension RollupIncrementalIndex {
    mutating func advanceHistoricalWindow(
        to newStart: Date,
        ownDayDeltasByTaskID: inout [UUID: [Date: Int]]
    ) -> Bool {
        guard newStart != recentWindowStart else { return false }
        guard newStart > recentWindowStart else {
            rebuildRecentBuckets(evaluatedAt: lastEvaluationDate, windowStart: newStart)
            recentWindowStart = newStart
            return true
        }

        let expiredDays = taskIDsByRecentDay.keys.filter { $0 < newStart }
        for day in expiredDays {
            for taskID in taskIDsByRecentDay.removeValue(forKey: day) ?? [] {
                guard let seconds = ownRecentDaySecondsByTaskID[taskID]?.removeValue(forKey: day),
                      seconds != 0 else {
                    continue
                }
                ownDayDeltasByTaskID[taskID, default: [:]][day, default: 0] -= seconds
                if ownRecentDaySecondsByTaskID[taskID]?.isEmpty == true {
                    ownRecentDaySecondsByTaskID.removeValue(forKey: taskID)
                }
            }
        }
        recentWindowStart = newStart
        return false
    }

    mutating func rebuildRecentBuckets(evaluatedAt now: Date, windowStart: Date) {
        recentWindowStart = windowStart
        ownRecentDaySecondsByTaskID.removeAll(keepingCapacity: true)
        taskIDsByRecentDay.removeAll(keepingCapacity: true)
        for segment in segmentByID.values {
            mergeOwnDayDelta(
                taskID: segment.taskID,
                deltas: recentDaySeconds(for: segment, evaluatedAt: now)
            )
        }
        rebuildSubtreeRecentBuckets()
        rebuildHistoricalPaces(taskIDs: Set(taskByID.keys))
    }

    mutating func applyOwnDayDeltas(taskID: UUID, deltas: [Date: Int]) {
        let nonzeroDeltas = deltas.filter { $0.value != 0 }
        guard !nonzeroDeltas.isEmpty else { return }
        mergeOwnDayDelta(taskID: taskID, deltas: nonzeroDeltas)
        for affectedID in [taskID] + ancestorIDs(of: taskID) {
            var buckets = subtreeRecentDaySecondsByTaskID[affectedID] ?? [:]
            for (day, delta) in nonzeroDeltas {
                buckets[day, default: 0] += delta
                if buckets[day, default: 0] <= 0 {
                    buckets.removeValue(forKey: day)
                }
            }
            if buckets.isEmpty {
                subtreeRecentDaySecondsByTaskID.removeValue(forKey: affectedID)
            } else {
                subtreeRecentDaySecondsByTaskID[affectedID] = buckets
            }
        }
    }

    mutating func mergeOwnDayDelta(taskID: UUID, deltas: [Date: Int]) {
        guard !deltas.isEmpty else { return }
        var buckets = ownRecentDaySecondsByTaskID[taskID] ?? [:]
        for (day, delta) in deltas where delta != 0 {
            buckets[day, default: 0] += delta
            if buckets[day, default: 0] <= 0 {
                buckets.removeValue(forKey: day)
                taskIDsByRecentDay[day]?.remove(taskID)
                if taskIDsByRecentDay[day]?.isEmpty == true {
                    taskIDsByRecentDay.removeValue(forKey: day)
                }
            } else {
                taskIDsByRecentDay[day, default: []].insert(taskID)
            }
        }
        if buckets.isEmpty {
            ownRecentDaySecondsByTaskID.removeValue(forKey: taskID)
        } else {
            ownRecentDaySecondsByTaskID[taskID] = buckets
        }
    }

    mutating func rebuildSubtreeRecentBuckets() {
        subtreeRecentDaySecondsByTaskID.removeAll(keepingCapacity: true)
        for taskID in postorderTaskIDs {
            var buckets = ownRecentDaySecondsByTaskID[taskID] ?? [:]
            for child in childrenByParent[taskID] ?? [] {
                mergeDayDeltas(
                    subtreeRecentDaySecondsByTaskID[child.id] ?? [:],
                    into: &buckets,
                    multiplier: 1
                )
            }
            if !buckets.isEmpty {
                subtreeRecentDaySecondsByTaskID[taskID] = buckets
            }
        }
    }

    mutating func rebuildHistoricalPaces(taskIDs: Set<UUID>) {
        for taskID in taskIDs {
            let buckets = subtreeRecentDaySecondsByTaskID[taskID] ?? [:]
            let activeTotals = buckets.values.filter { $0 > 0 }
            if activeTotals.isEmpty {
                historicalPaceByTaskID.removeValue(forKey: taskID)
            } else {
                historicalPaceByTaskID[taskID] = TaskRollupHistoricalPace(
                    averageSeconds: activeTotals.reduce(0, +) / activeTotals.count,
                    activeDayCount: activeTotals.count
                )
            }
        }
    }

    func recentDaySeconds(
        for segment: LedgerSegmentSnapshot,
        evaluatedAt now: Date
    ) -> [Date: Int] {
        guard let interval = TrackedTimePolicy.interval(
            startedAt: segment.startedAt,
            endedAt: segment.endedAt,
            now: now,
            clippedTo: DateInterval(start: recentWindowStart, end: now)
        ) else {
            return [:]
        }
        return TimeAggregationService().secondsByDay(
            intervals: [interval],
            calendar: calendar
        )
    }

    func historicalWindowStart(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(
            byAdding: .day,
            value: -(Self.historicalPaceDayCount - 1),
            to: today
        ) ?? today.addingTimeInterval(-Double(Self.historicalPaceDayCount - 1) * 86_400)
    }

    func mergeDayDeltas(
        _ source: [Date: Int],
        into target: inout [Date: Int],
        multiplier: Int
    ) {
        for (day, seconds) in source {
            target[day, default: 0] += seconds * multiplier
        }
    }
}
