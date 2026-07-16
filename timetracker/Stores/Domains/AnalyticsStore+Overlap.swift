import Foundation

extension AnalyticsStore {
    func overlapSegments(
        items: [AnalyticsBoundedSegment],
        tasks: [TaskNode],
        sessions: [TimeSession]
    ) -> [OverlapAnalyticsPoint] {
        let canonicalItems = canonicalOverlapItems(items)
        guard canonicalItems.count > 1 else { return [] }

        let participantsByTaskID = overlapParticipants(
            taskIDs: Set(canonicalItems.map { $0.segment.taskID }),
            tasks: tasks,
            sessions: sessions
        )
        let rawWindows = sweepOverlapWindows(
            canonicalItems,
            participantsByTaskID: participantsByTaskID
        )
        return materializeOverlapWindows(
            rawWindows,
            expectedExcessSeconds: overview(items: canonicalItems).overlapSeconds
        )
    }

    private func canonicalOverlapItems(_ items: [AnalyticsBoundedSegment]) -> [AnalyticsBoundedSegment] {
        let canonicalByID = items.reduce(into: [UUID: AnalyticsBoundedSegment]()) { result, item in
            guard item.interval.end > item.interval.start else { return }
            guard let existing = result[item.segment.id] else {
                result[item.segment.id] = item
                return
            }

            if overlapItemPrecedes(existing, item) {
                result[item.segment.id] = item
            }
        }
        return canonicalByID.values.sorted {
            $0.segment.id.uuidString < $1.segment.id.uuidString
        }
    }

    private func overlapItemPrecedes(
        _ lhs: AnalyticsBoundedSegment,
        _ rhs: AnalyticsBoundedSegment
    ) -> Bool {
        if lhs.segment.updatedAt != rhs.segment.updatedAt {
            return lhs.segment.updatedAt < rhs.segment.updatedAt
        }
        if lhs.segment.createdAt != rhs.segment.createdAt {
            return lhs.segment.createdAt < rhs.segment.createdAt
        }
        if lhs.segment.deviceID != rhs.segment.deviceID {
            return lhs.segment.deviceID < rhs.segment.deviceID
        }
        if lhs.interval.start != rhs.interval.start {
            return lhs.interval.start < rhs.interval.start
        }
        return lhs.interval.end < rhs.interval.end
    }
}
