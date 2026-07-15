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
        refreshUnchangedActiveSegments: Bool
    ) {
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
                (refreshUnchangedActiveSegments && after?.endedAt == nil)
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
                index(after, now: now, calendar: calendar)
            } else {
                segmentByID.removeValue(forKey: id)
                segmentSnapshotByID.removeValue(forKey: id)
                activeSegmentIDs.remove(id)
            }
        }

        segmentIndexEvaluationDate = now
        segmentIndexCalendar = calendar
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

    mutating func updateFlatSegment(
        id: UUID,
        previousSnapshot: LedgerSegmentSnapshot?,
        model: TimeSegment?
    ) {
        if let existingIndex = segmentArrayIndexByID[id] {
            guard let model else {
                allSegments.remove(at: existingIndex)
                segmentArrayIndexByID.removeValue(forKey: id)
                reindexFlatSegments(from: existingIndex)
                return
            }

            if previousSnapshot?.startedAt == model.startedAt {
                // SwiftData returns the same reference after an in-context
                // edit. Avoid copying the shared flat-array buffer when its
                // model already exposes the new values.
                if allSegments[existingIndex] !== model {
                    allSegments[existingIndex] = model
                }
                return
            }

            allSegments.remove(at: existingIndex)
            segmentArrayIndexByID.removeValue(forKey: id)
            reindexFlatSegments(from: existingIndex)
        }

        guard let model else { return }
        let insertionIndex = allSegments.partitioningIndex { segmentStartOrder($0, model) }
        allSegments.insert(model, at: insertionIndex)
        reindexFlatSegments(from: insertionIndex)
    }

    mutating func reindexFlatSegments(from startIndex: Int) {
        guard startIndex < allSegments.count else { return }
        for index in startIndex..<allSegments.count {
            segmentArrayIndexByID[allSegments[index].id] = index
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
        let end = snapshot.endedAt ?? now
        guard end > snapshot.startedAt else { return [] }
        return dayKeys(
            overlapping: DateInterval(start: snapshot.startedAt, end: end),
            calendar: calendar
        )
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

    func segmentStartOrder(_ lhs: TimeSegment, _ rhs: TimeSegment) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private extension Array {
    func partitioningIndex(where belongsBefore: (Element) -> Bool) -> Int {
        var lowerBound = startIndex
        var upperBound = endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + distance(from: lowerBound, to: upperBound) / 2
            if belongsBefore(self[middle]) {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }
}
