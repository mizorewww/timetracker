import Foundation
import HeapModule

nonisolated extension AnalyticsVisualOverlapService {
    func sweepOverlapWindows(
        _ segments: [AnalyticsVisualBoundedSegment],
        participantsByTaskID: [UUID: OverlapAnalyticsParticipant]
    ) -> [AnalyticsVisualRawOverlapWindow] {
        var events = segments.flatMap { segment in
            [
                AnalyticsVisualOverlapEvent(
                    date: segment.interval.start,
                    kind: .start,
                    segmentID: segment.id,
                    taskID: segment.taskID
                ),
                AnalyticsVisualOverlapEvent(
                    date: segment.interval.end,
                    kind: .end,
                    segmentID: segment.id,
                    taskID: segment.taskID
                ),
            ]
        }
        events.sort { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            if lhs.kind != rhs.kind {
                return lhs.kind.rawValue < rhs.kind.rawValue
            }
            return lhs.segmentID.uuidString < rhs.segmentID.uuidString
        }

        var activeSegmentIDs = Set<UUID>()
        var activeSegmentCountByTaskID: [UUID: Int] = [:]
        var participantHeap = Heap<OverlapAnalyticsParticipant>()
        var residentParticipantIDs = Set<UUID>()
        var rawWindows: [AnalyticsVisualRawOverlapWindow] = []
        var cursor = events.first?.date
        var index = events.startIndex
        var canMergeAcrossCursor = false

        while index < events.endIndex {
            guard Task.isCancelled == false else { return [] }
            let date = events[index].date
            if let start = cursor, date > start, activeSegmentIDs.count > 1 {
                let visibleParticipants = firstActiveParticipants(
                    limit: 3,
                    heap: &participantHeap,
                    residentParticipantIDs: &residentParticipantIDs,
                    activeSegmentCountByTaskID: activeSegmentCountByTaskID
                )
                let window = AnalyticsVisualRawOverlapWindow(
                    start: start,
                    end: date,
                    concurrentSegmentCount: activeSegmentIDs.count,
                    participantCount: activeSegmentCountByTaskID.count,
                    visibleParticipants: visibleParticipants
                )
                if canMergeAcrossCursor,
                   let previous = rawWindows.last,
                   previous.end == start,
                   previous.concurrentSegmentCount == window.concurrentSegmentCount,
                   previous.participantCount == window.participantCount,
                   previous.visibleParticipants == window.visibleParticipants
                {
                    rawWindows[rawWindows.count - 1].end = date
                } else {
                    rawWindows.append(window)
                }
            }

            var boundaryEnd = index
            var affectedTaskIDs = Set<UUID>()
            while boundaryEnd < events.endIndex, events[boundaryEnd].date == date {
                affectedTaskIDs.insert(events[boundaryEnd].taskID)
                boundaryEnd = events.index(after: boundaryEnd)
            }
            let activeSegmentCountBeforeBoundary = activeSegmentIDs.count
            let membershipBeforeBoundary = affectedTaskIDs.reduce(into: [UUID: Bool]()) {
                result,
                taskID in
                result[taskID] = activeSegmentCountByTaskID[taskID] != nil
            }

            while index < boundaryEnd, events[index].kind == .end {
                let event = events[index]
                if activeSegmentIDs.remove(event.segmentID) != nil {
                    let remaining = max(0, (activeSegmentCountByTaskID[event.taskID] ?? 1) - 1)
                    if remaining == 0 {
                        activeSegmentCountByTaskID.removeValue(forKey: event.taskID)
                    } else {
                        activeSegmentCountByTaskID[event.taskID] = remaining
                    }
                }
                index = events.index(after: index)
            }
            while index < boundaryEnd {
                let event = events[index]
                if activeSegmentIDs.insert(event.segmentID).inserted {
                    let wasInactive = activeSegmentCountByTaskID[event.taskID] == nil
                    activeSegmentCountByTaskID[event.taskID, default: 0] += 1
                    if wasInactive,
                       residentParticipantIDs.insert(event.taskID).inserted,
                       let participant = participantsByTaskID[event.taskID]
                    {
                        participantHeap.insert(participant)
                    }
                }
                index = events.index(after: index)
            }

            let participantMembershipUnchanged = affectedTaskIDs.allSatisfy { taskID in
                membershipBeforeBoundary[taskID] == (activeSegmentCountByTaskID[taskID] != nil)
            }
            canMergeAcrossCursor = activeSegmentCountBeforeBoundary == activeSegmentIDs.count
                && participantMembershipUnchanged
            cursor = date
        }
        return rawWindows
    }

    func firstActiveParticipants(
        limit: Int,
        heap: inout Heap<OverlapAnalyticsParticipant>,
        residentParticipantIDs: inout Set<UUID>,
        activeSegmentCountByTaskID: [UUID: Int]
    ) -> [OverlapAnalyticsParticipant] {
        var participants: [OverlapAnalyticsParticipant] = []
        while participants.count < limit {
            while let candidate = heap.min,
                  activeSegmentCountByTaskID[candidate.id] == nil
            {
                _ = heap.popMin()
                residentParticipantIDs.remove(candidate.id)
            }
            guard let participant = heap.popMin() else { break }
            participants.append(participant)
        }
        for participant in participants {
            heap.insert(participant)
        }
        return participants
    }
}

nonisolated enum AnalyticsVisualOverlapEventKind: Int {
    case end
    case start
}

nonisolated struct AnalyticsVisualOverlapEvent {
    let date: Date
    let kind: AnalyticsVisualOverlapEventKind
    let segmentID: UUID
    let taskID: UUID
}

nonisolated struct AnalyticsVisualRawOverlapWindow {
    let start: Date
    var end: Date
    let concurrentSegmentCount: Int
    let participantCount: Int
    let visibleParticipants: [OverlapAnalyticsParticipant]
}
