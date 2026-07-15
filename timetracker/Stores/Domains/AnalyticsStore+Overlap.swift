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
        var events = canonicalItems.flatMap { item in
            [
                OverlapSweepEvent(
                    date: item.interval.start,
                    kind: .start,
                    segmentID: item.segment.id,
                    taskID: item.segment.taskID
                ),
                OverlapSweepEvent(
                    date: item.interval.end,
                    kind: .end,
                    segmentID: item.segment.id,
                    taskID: item.segment.taskID
                )
            ]
        }
        events.sort(by: overlapEventPrecedes)

        var activeSegmentIDs = Set<UUID>()
        var activeSegmentCountByTaskID: [UUID: Int] = [:]
        var participantHeap = OverlapParticipantMinHeap()
        var residentParticipantIDs = Set<UUID>()
        var rawWindows: [RawOverlapWindow] = []
        var cursor = events.first?.date
        var index = events.startIndex
        var canMergeAcrossCursor = false

        while index < events.endIndex {
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
                   previous.visibleParticipants == window.visibleParticipants {
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
                       let participant = participantsByTaskID[event.taskID] {
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

    private func overlapParticipants(
        taskIDs: Set<UUID>,
        tasks: [TaskNode],
        sessions: [TimeSession]
    ) -> [UUID: OverlapAnalyticsParticipant] {
        let taskByID = tasks.latestByID()
        let fallbackTitleByTaskID = sessions.deduplicatedByID().reduce(
            into: [UUID: TimeSession]()
        ) { result, session in
            guard session.deletedAt == nil,
                  session.titleSnapshot?.isEmpty == false,
                  taskIDs.contains(session.taskID) else {
                return
            }
            guard let existing = result[session.taskID] else {
                result[session.taskID] = session
                return
            }
            if overlapSessionPrecedes(existing, session) {
                result[session.taskID] = session
            }
        }

        return taskIDs.reduce(into: [UUID: OverlapAnalyticsParticipant]()) { result, taskID in
            let title = taskByID[taskID]?.title
                ?? fallbackTitleByTaskID[taskID]?.titleSnapshot
                ?? AppStrings.localized("task.deleted")
            result[taskID] = OverlapAnalyticsParticipant(id: taskID, title: title)
        }
    }

    private func overlapSessionPrecedes(_ lhs: TimeSession, _ rhs: TimeSession) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt < rhs.updatedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func firstActiveParticipants(
        limit: Int,
        heap: inout OverlapParticipantMinHeap,
        residentParticipantIDs: inout Set<UUID>,
        activeSegmentCountByTaskID: [UUID: Int]
    ) -> [OverlapAnalyticsParticipant] {
        var participants: [OverlapAnalyticsParticipant] = []

        while participants.count < limit {
            while let candidate = heap.min,
                  activeSegmentCountByTaskID[candidate.id] == nil {
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

    private func materializeOverlapWindows(
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

    /// Duration models expose whole seconds. Distributing subsecond remainders
    /// here preserves the invariant that detail rows sum exactly to Gross-Wall.
    private func reconcileOverlapSeconds(
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

    private func overlapEventPrecedes(_ lhs: OverlapSweepEvent, _ rhs: OverlapSweepEvent) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }
        if lhs.kind != rhs.kind {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.segmentID.uuidString < rhs.segmentID.uuidString
    }

    private func overlapPointPrecedes(_ lhs: OverlapAnalyticsPoint, _ rhs: OverlapAnalyticsPoint) -> Bool {
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

    private func rawWindowPrecedes(_ lhs: RawOverlapWindow, _ rhs: RawOverlapWindow) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        if lhs.end != rhs.end {
            return lhs.end < rhs.end
        }
        return lhs.concurrentSegmentCount > rhs.concurrentSegmentCount
    }
}

private enum OverlapSweepEventKind: Int {
    case end
    case start
}

private struct OverlapSweepEvent {
    let date: Date
    let kind: OverlapSweepEventKind
    let segmentID: UUID
    let taskID: UUID
}

private struct RawOverlapWindow {
    let start: Date
    var end: Date
    let concurrentSegmentCount: Int
    let participantCount: Int
    let visibleParticipants: [OverlapAnalyticsParticipant]
}

private struct OverlapParticipantMinHeap {
    private var elements: [OverlapAnalyticsParticipant] = []

    var min: OverlapAnalyticsParticipant? {
        elements.first
    }

    mutating func insert(_ element: OverlapAnalyticsParticipant) {
        elements.append(element)
        siftUp(from: elements.count - 1)
    }

    mutating func popMin() -> OverlapAnalyticsParticipant? {
        guard !elements.isEmpty else { return nil }
        if elements.count == 1 {
            return elements.removeLast()
        }

        let minimum = elements[0]
        elements[0] = elements.removeLast()
        siftDown(from: 0)
        return minimum
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        var parent = parentIndex(of: child)

        while child > 0, precedes(elements[child], elements[parent]) {
            elements.swapAt(child, parent)
            child = parent
            parent = parentIndex(of: child)
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index

        while true {
            let left = leftChildIndex(of: parent)
            let right = rightChildIndex(of: parent)
            var candidate = parent

            if left < elements.count, precedes(elements[left], elements[candidate]) {
                candidate = left
            }
            if right < elements.count, precedes(elements[right], elements[candidate]) {
                candidate = right
            }
            guard candidate != parent else { return }

            elements.swapAt(parent, candidate)
            parent = candidate
        }
    }

    private func precedes(
        _ lhs: OverlapAnalyticsParticipant,
        _ rhs: OverlapAnalyticsParticipant
    ) -> Bool {
        if lhs.title != rhs.title {
            return lhs.title < rhs.title
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func parentIndex(of index: Int) -> Int {
        (index - 1) / 2
    }

    private func leftChildIndex(of index: Int) -> Int {
        (2 * index) + 1
    }

    private func rightChildIndex(of index: Int) -> Int {
        (2 * index) + 2
    }
}
