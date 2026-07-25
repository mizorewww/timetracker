import Foundation

extension LedgerStore {
    static let maximumIndexedDayCount = 366

    func segmentIDs(overlapping intervals: [DateInterval], now: Date) -> Set<UUID> {
        intervals.reduce(into: Set<UUID>()) { result, interval in
            if exceedsDayIndexLimit(interval, calendar: segmentIndexCalendar) {
                for (id, snapshot) in segmentSnapshotByID
                    where snapshot.overlaps(interval, at: now)
                {
                    result.insert(id)
                }
                return
            }
            for id in longSpanSegmentIDs {
                guard segmentSnapshotByID[id]?.overlaps(interval, at: now) == true else {
                    continue
                }
                result.insert(id)
            }
            for day in dayKeys(overlapping: interval, calendar: segmentIndexCalendar) {
                for id in segmentIDsByDay[day] ?? [] {
                    guard segmentSnapshotByID[id]?.overlaps(interval, at: now) == true else {
                        continue
                    }
                    result.insert(id)
                }
            }
        }
    }

    func taskScopedSegmentIDs(
        overlapping interval: DateInterval,
        taskIDs: Set<UUID>,
        evaluatedAt cutoff: Date,
        clockReference: Date
    ) -> Set<UUID> {
        guard taskIDs.isEmpty == false else { return [] }
        if segmentCount(forTaskIDs: taskIDs) <= estimatedSegmentCandidateUpperBound(
            overlapping: interval,
            clockReference: clockReference
        ) {
            return segmentIDs(forTaskIDs: taskIDs).filter { id in
                segmentSnapshotByID[id]?.overlaps(interval, at: cutoff) == true
            }
        }
        return segmentCandidateIDs(
            overlapping: interval,
            evaluatedAt: cutoff,
            clockReference: clockReference
        ).filter { id in
            guard let snapshot = segmentSnapshotByID[id] else { return false }
            return taskIDs.contains(snapshot.taskID)
        }
    }

    private func estimatedSegmentCandidateUpperBound(
        overlapping interval: DateInterval,
        clockReference: Date
    ) -> Int {
        guard clockReference >= segmentIndexEvaluationDate,
              exceedsDayIndexLimit(interval, calendar: segmentIndexCalendar) == false
        else {
            return segmentSnapshotByID.count
        }
        let dayBucketCount = dayKeys(
            overlapping: interval,
            calendar: segmentIndexCalendar
        ).reduce(0) { result, day in
            result + (segmentIDsByDay[day]?.count ?? 0)
        }
        return min(
            segmentSnapshotByID.count,
            dayBucketCount + longSpanSegmentIDs.count + timeSensitiveSegmentIDs.count
        )
    }

    func exceedsDayIndexLimit(
        _ interval: DateInterval,
        calendar: Calendar
    ) -> Bool {
        let firstDay = calendar.startOfDay(for: interval.start)
        guard let exclusiveLimit = calendar.date(
            byAdding: .day,
            value: Self.maximumIndexedDayCount,
            to: firstDay
        ) else {
            return true
        }
        return interval.end > exclusiveLimit
    }
}
