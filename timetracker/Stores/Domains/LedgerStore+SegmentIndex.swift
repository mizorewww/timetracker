import Foundation
extension LedgerStore {
    mutating func rebuildSegmentIndexes(
        segments: [TimeSegment],
        now: Date,
        calendar: Calendar
    ) {
        allSegments = segments
            .deduplicatedByID()
            .filter { $0.deletedAt == nil }
            .sorted(by: segmentStartOrder)
        segmentByID = Dictionary(uniqueKeysWithValues: allSegments.map { ($0.id, $0) })
        segmentSnapshotByID = Dictionary(uniqueKeysWithValues: allSegments.map {
            ($0.id, LedgerSegmentSnapshot($0))
        })
        segmentArrayIndexByID = Dictionary(uniqueKeysWithValues: allSegments.indices.map {
            (allSegments[$0].id, $0)
        })
        segmentIndexEvaluationDate = now
        segmentIndexCalendar = calendar
        activeSegmentIDs = Set(segmentSnapshotByID.values.filter { $0.endedAt == nil }.map(\.id))
        timeSensitiveSegmentIDs = Set(
            segmentSnapshotByID.values.filter { $0.isTimeSensitive(at: now) }.map(\.id)
        )
        rebuildRecordIndexes()
        segmentIDsByDay.removeAll(keepingCapacity: true)
        for snapshot in segmentSnapshotByID.values {
            index(snapshot, now: now, calendar: calendar)
        }
    }

    mutating func rebuildSegmentDayIndex(now: Date, calendar: Calendar) {
        segmentIDsByDay.removeAll(keepingCapacity: true)
        segmentIndexEvaluationDate = now
        segmentIndexCalendar = calendar
        for snapshot in segmentSnapshotByID.values {
            index(snapshot, now: now, calendar: calendar)
        }
    }

    mutating func replaceSegments(
        ids: Set<UUID>,
        with fetchedSegments: [TimeSegment],
        now: Date,
        calendar: Calendar,
        refreshUnchangedTimeSensitiveSegments: Bool
    ) {
        let isClockRewind = now < segmentIndexEvaluationDate
        let fetchedByID = fetchedSegments
            .deduplicatedByID()
            .filter { $0.deletedAt == nil }
            .reduce(into: [UUID: TimeSegment]()) { $0[$1.id] = $1 }

        for id in ids {
            let before = segmentSnapshotByID[id]
            let afterModel = fetchedByID[id]
            let after: LedgerSegmentSnapshot?
            if let afterModel {
                after = LedgerSegmentSnapshot(afterModel)
            } else {
                after = nil
            }
            let shouldRefresh = before != after ||
                (refreshUnchangedTimeSensitiveSegments && after?.isTimeSensitive(at: now) == true)
            if shouldRefresh {
                recordRollupChange(id: id, before: before, after: after)
            }

            if let before {
                unindexRecord(before)
                unindex(before, now: segmentIndexEvaluationDate, calendar: segmentIndexCalendar)
            }
            updateFlatSegment(id: id, previousSnapshot: before, model: afterModel)
            if let afterModel, let after {
                indexRecord(after)
                segmentByID[id] = afterModel
                segmentSnapshotByID[id] = after
                if after.endedAt == nil {
                    activeSegmentIDs.insert(id)
                } else {
                    activeSegmentIDs.remove(id)
                }
                if after.isTimeSensitive(at: now) {
                    timeSensitiveSegmentIDs.insert(id)
                } else {
                    timeSensitiveSegmentIDs.remove(id)
                }
                index(after, now: now, calendar: calendar)
            } else {
                segmentByID.removeValue(forKey: id)
                segmentSnapshotByID.removeValue(forKey: id)
                activeSegmentIDs.remove(id)
                timeSensitiveSegmentIDs.remove(id)
            }
        }

        segmentIndexEvaluationDate = now
        segmentIndexCalendar = calendar
        if isClockRewind {
            timeSensitiveSegmentIDs = Set(
                segmentSnapshotByID.values.filter { $0.isTimeSensitive(at: now) }.map(\.id)
            )
        }
        rollupChanges = pendingRollupChangeByID.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
    }

    mutating func recordRollupChange(
        id: UUID,
        before: LedgerSegmentSnapshot?,
        after: LedgerSegmentSnapshot?
    ) {
        if let pending = pendingRollupChangeByID[id] {
            pendingRollupChangeByID[id] = LedgerSegmentChange(
                id: id,
                before: pending.before,
                after: after
            )
        } else {
            pendingRollupChangeByID[id] = LedgerSegmentChange(
                id: id,
                before: before,
                after: after
            )
        }
    }

    func segmentIDs(overlapping intervals: [DateInterval], now: Date) -> Set<UUID> {
        intervals.reduce(into: Set<UUID>()) { result, interval in
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

    mutating func index(_ snapshot: LedgerSegmentSnapshot, now: Date, calendar: Calendar) {
        for day in dayKeys(for: snapshot, now: now, calendar: calendar) {
            segmentIDsByDay[day, default: []].insert(snapshot.id)
        }
    }

    mutating func unindex(_ snapshot: LedgerSegmentSnapshot, now: Date, calendar: Calendar) {
        for day in dayKeys(for: snapshot, now: now, calendar: calendar) {
            segmentIDsByDay[day]?.remove(snapshot.id)
            if segmentIDsByDay[day]?.isEmpty == true {
                segmentIDsByDay.removeValue(forKey: day)
            }
        }
    }

    func dayKeys(for snapshot: LedgerSegmentSnapshot, now: Date, calendar: Calendar) -> [Date] {
        guard let interval = TrackedTimePolicy.interval(
            startedAt: snapshot.startedAt,
            endedAt: snapshot.endedAt,
            now: now
        ) else {
            return []
        }
        return dayKeys(overlapping: interval, calendar: calendar)
    }

    func dayKeys(overlapping interval: DateInterval, calendar: Calendar) -> [Date] {
        guard interval.duration > 0 else { return [] }
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
    func uniqueSegments(_ segments: [TimeSegment]) -> [TimeSegment] {
        segments.deduplicatedByID().filter { $0.deletedAt == nil }
    }

}
