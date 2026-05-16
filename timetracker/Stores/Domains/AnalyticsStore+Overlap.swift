import Foundation

extension AnalyticsStore {
    func overlapSegments(
        segments: [TimeSegment],
        tasks: [TaskNode],
        sessions: [TimeSession],
        now: Date
    ) -> [OverlapAnalyticsPoint] {
        struct Event {
            let date: Date
            let isStart: Bool
            let segmentID: UUID
        }

        let taskByID = tasks.latestByID()
        let sessionsByTaskID = Dictionary(grouping: sessions.deduplicatedByID(), by: \.taskID)
        let boundedSegments = segments.deduplicatedByID().compactMap { segment -> BoundedOverlapSegment? in
            let end = segment.endedAt ?? now
            guard segment.deletedAt == nil, end > segment.startedAt else { return nil }
            return BoundedOverlapSegment(
                segment: segment,
                end: end,
                title: displayTitle(for: segment, taskByID: taskByID, sessionsByTaskID: sessionsByTaskID)
            )
        }
        let boundedByID = boundedSegments.reduce(into: [UUID: BoundedOverlapSegment]()) { result, item in
            result[item.segment.id] = item
        }

        var events: [Event] = []
        for item in boundedSegments {
            events.append(Event(date: item.segment.startedAt, isStart: true, segmentID: item.segment.id))
            events.append(Event(date: item.end, isStart: false, segmentID: item.segment.id))
        }

        events.sort { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.isStart == false && rhs.isStart == true
            }
            return lhs.date < rhs.date
        }

        var active: [UUID: BoundedOverlapSegment] = [:]
        var overlaps: [OverlapAnalyticsPoint] = []
        var cursor = events.first?.date
        var index = events.startIndex

        while index < events.endIndex {
            let date = events[index].date
            if let start = cursor, date > start, active.count > 1 {
                let pair = firstTwoActiveOverlaps(active.values)
                if let first = pair.first, let second = pair.second {
                    overlaps.append(
                        OverlapAnalyticsPoint(
                            start: start,
                            end: date,
                            firstTitle: first.title,
                            secondTitle: second.title
                        )
                    )
                }
            }

            while index < events.endIndex, events[index].date == date, events[index].isStart == false {
                active.removeValue(forKey: events[index].segmentID)
                index = events.index(after: index)
            }
            while index < events.endIndex, events[index].date == date, events[index].isStart == true {
                if let bounded = boundedByID[events[index].segmentID] {
                    active[events[index].segmentID] = bounded
                }
                index = events.index(after: index)
            }
            cursor = date
        }

        return overlaps.sorted { $0.durationSeconds > $1.durationSeconds }
    }

    private func firstTwoActiveOverlaps(
        _ active: Dictionary<UUID, BoundedOverlapSegment>.Values
    ) -> (first: BoundedOverlapSegment?, second: BoundedOverlapSegment?) {
        var first: BoundedOverlapSegment?
        var second: BoundedOverlapSegment?

        for candidate in active {
            if first.map({ overlapPrecedes(candidate, $0) }) ?? true {
                second = first
                first = candidate
            } else if second.map({ overlapPrecedes(candidate, $0) }) ?? true {
                second = candidate
            }
        }

        return (first, second)
    }

    private func overlapPrecedes(_ lhs: BoundedOverlapSegment, _ rhs: BoundedOverlapSegment) -> Bool {
        if lhs.segment.startedAt == rhs.segment.startedAt {
            if lhs.title == rhs.title {
                return lhs.segment.id.uuidString < rhs.segment.id.uuidString
            }
            return lhs.title < rhs.title
        }
        return lhs.segment.startedAt < rhs.segment.startedAt
    }

    private func displayTitle(
        for segment: TimeSegment,
        taskByID: [UUID: TaskNode],
        sessionsByTaskID: [UUID: [TimeSession]]
    ) -> String {
        taskByID[segment.taskID]?.title ?? sessionsByTaskID[segment.taskID]?.first?.titleSnapshot ?? AppStrings.localized("task.deleted")
    }
}

private struct BoundedOverlapSegment {
    let segment: TimeSegment
    let end: Date
    let title: String
}
