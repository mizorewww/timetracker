import Foundation
import HeapModule

nonisolated struct OverlapSweepSegment: Sendable {
    let id: UUID
    let taskID: UUID
    let interval: DateInterval
}

nonisolated struct RawOverlapWindow: Sendable {
    let start: Date
    var end: Date
    let concurrentSegmentCount: Int
    let participantCount: Int
    let visibleParticipants: [OverlapAnalyticsParticipant]
}

nonisolated enum OverlapWindowSweepEngine {
    static func overlapPoints(
        segments: [OverlapSweepSegment],
        participantsByTaskID: [UUID: OverlapAnalyticsParticipant],
        expectedExcessSeconds: Int,
        checksCancellation: Bool = false
    ) -> [OverlapAnalyticsPoint] {
        let rawWindows = sweepOverlapWindows(
            segments,
            participantsByTaskID: participantsByTaskID,
            checksCancellation: checksCancellation
        )
        if checksCancellation, Task.isCancelled {
            return []
        }
        return materializeOverlapWindows(
            rawWindows,
            expectedExcessSeconds: expectedExcessSeconds
        )
    }

    static func sweepOverlapWindows(
        _ segments: [OverlapSweepSegment],
        participantsByTaskID: [UUID: OverlapAnalyticsParticipant],
        checksCancellation: Bool = false
    ) -> [RawOverlapWindow] {
        var events = segments.flatMap { segment in
            [
                OverlapSweepEvent(
                    date: segment.interval.start,
                    kind: .start,
                    segmentID: segment.id,
                    taskID: segment.taskID
                ),
                OverlapSweepEvent(
                    date: segment.interval.end,
                    kind: .end,
                    segmentID: segment.id,
                    taskID: segment.taskID
                ),
            ]
        }
        events.sort(by: overlapEventPrecedes)

        var activeSegmentIDs = Set<UUID>()
        var activeSegmentCountByTaskID: [UUID: Int] = [:]
        var participantHeap = Heap<OverlapAnalyticsParticipant>()
        var residentParticipantIDs = Set<UUID>()
        var rawWindows: [RawOverlapWindow] = []
        var cursor = events.first?.date
        var index = events.startIndex
        var canMergeAcrossCursor = false

        while index < events.endIndex {
            if checksCancellation, Task.isCancelled {
                return []
            }
            let date = events[index].date
            if let start = cursor, date > start, activeSegmentIDs.count > 1 {
                let visibleParticipants = firstActiveParticipants(
                    limit: 3,
                    heap: &participantHeap,
                    residentParticipantIDs: &residentParticipantIDs,
                    activeSegmentCountByTaskID: activeSegmentCountByTaskID
                )
                let window = RawOverlapWindow(
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
            let membershipBeforeBoundary = affectedTaskIDs.reduce(into: [UUID: Bool]()) { result, taskID in
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

    static func materializeOverlapWindows(
        _ rawWindows: [RawOverlapWindow],
        expectedExcessSeconds: Int
    ) -> [OverlapAnalyticsPoint] {
        guard !rawWindows.isEmpty else {
            assert(expectedExcessSeconds == 0)
            return []
        }

        let exactExcess = rawWindows.map { window in
            max(
                0,
                window.end.timeIntervalSince(window.start)
                    * Double(max(0, window.concurrentSegmentCount - 1))
            )
        }
        var allocatedExcess = exactExcess.map { Int($0.rounded(.down)) }
        reconcileOverlapSeconds(
            &allocatedExcess,
            exactExcess: exactExcess,
            windows: rawWindows,
            expectedTotal: max(0, expectedExcessSeconds)
        )

        let points = zip(rawWindows.indices, rawWindows).map { index, window in
            OverlapAnalyticsPoint(
                start: window.start,
                end: window.end,
                concurrentSegmentCount: window.concurrentSegmentCount,
                participantCount: window.participantCount,
                visibleParticipants: window.visibleParticipants,
                wallDurationSeconds: max(0, Int(window.end.timeIntervalSince(window.start))),
                excessDurationSeconds: allocatedExcess[index]
            )
        }
        .sorted(by: overlapPointPrecedes)
        assert(points.reduce(0) { $0 + $1.excessDurationSeconds } == expectedExcessSeconds)
        return points
    }

    private static func reconcileOverlapSeconds(
        _ allocated: inout [Int],
        exactExcess: [TimeInterval],
        windows: [RawOverlapWindow],
        expectedTotal: Int
    ) {
        var difference = expectedTotal - allocated.reduce(0, +)
        guard difference != 0, !allocated.isEmpty else { return }

        let indexes = allocated.indices.sorted { lhs, rhs in
            let lhsRemainder = exactExcess[lhs] - exactExcess[lhs].rounded(.down)
            let rhsRemainder = exactExcess[rhs] - exactExcess[rhs].rounded(.down)
            if lhsRemainder != rhsRemainder {
                return difference > 0
                    ? lhsRemainder > rhsRemainder
                    : lhsRemainder < rhsRemainder
            }
            return rawWindowPrecedes(windows[lhs], windows[rhs])
        }

        var allocationCursor = 0
        while difference != 0 {
            let target = indexes[allocationCursor % indexes.count]
            if difference > 0 {
                allocated[target] += 1
                difference -= 1
            } else if allocated[target] > 0 {
                allocated[target] -= 1
                difference += 1
            }
            allocationCursor += 1
        }
    }

    private static func firstActiveParticipants(
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

    private static func overlapEventPrecedes(_ lhs: OverlapSweepEvent, _ rhs: OverlapSweepEvent) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        if lhs.kind != rhs.kind {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.segmentID < rhs.segmentID
    }

    private static func overlapPointPrecedes(_ lhs: OverlapAnalyticsPoint, _ rhs: OverlapAnalyticsPoint) -> Bool {
        if lhs.excessDurationSeconds != rhs.excessDurationSeconds {
            return lhs.excessDurationSeconds > rhs.excessDurationSeconds
        }
        if lhs.wallDurationSeconds != rhs.wallDurationSeconds {
            return lhs.wallDurationSeconds > rhs.wallDurationSeconds
        }
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        if lhs.end != rhs.end {
            return lhs.end < rhs.end
        }
        if lhs.concurrentSegmentCount != rhs.concurrentSegmentCount {
            return lhs.concurrentSegmentCount > rhs.concurrentSegmentCount
        }
        return lhs.visibleParticipants.map { $0.id.uuidString }.lexicographicallyPrecedes(
            rhs.visibleParticipants.map { $0.id.uuidString }
        )
    }

    private static func rawWindowPrecedes(_ lhs: RawOverlapWindow, _ rhs: RawOverlapWindow) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        if lhs.end != rhs.end {
            return lhs.end < rhs.end
        }
        return lhs.concurrentSegmentCount > rhs.concurrentSegmentCount
    }
}

private nonisolated enum OverlapSweepEventKind: Int {
    case end
    case start
}

private nonisolated struct OverlapSweepEvent {
    let date: Date
    let kind: OverlapSweepEventKind
    let segmentID: UUID
    let taskID: UUID
}
