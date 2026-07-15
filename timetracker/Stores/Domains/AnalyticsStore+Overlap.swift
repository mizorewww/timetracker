import Foundation

extension AnalyticsStore {
    func overlapSegments(
        items: [AnalyticsBoundedSegment],
        tasks: [TaskNode],
        sessions: [TimeSession]
    ) -> [OverlapAnalyticsPoint] {
        struct Event {
            let date: Date
            let isStart: Bool
            let segmentID: UUID
        }

        let taskByID = tasks.latestByID()
        let sessionsByTaskID = Dictionary(grouping: sessions.deduplicatedByID(), by: \.taskID)
        let overlapItems = items.map { item in
            return BoundedOverlapSegment(
                segment: item.segment,
                interval: item.interval,
                title: displayTitle(for: item.segment, taskByID: taskByID, sessionsByTaskID: sessionsByTaskID)
            )
        }
        let boundedByID = overlapItems.reduce(into: [UUID: BoundedOverlapSegment]()) { result, item in
            result[item.segment.id] = item
        }

        var events: [Event] = []
        for item in overlapItems {
            events.append(Event(date: item.interval.start, isStart: true, segmentID: item.segment.id))
            events.append(Event(date: item.interval.end, isStart: false, segmentID: item.segment.id))
        }

        events.sort { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.isStart == false && rhs.isStart == true
            }
            return lhs.date < rhs.date
        }

        var activeIDs = Set<UUID>()
        var activeHeap = OverlapMinHeap { lhs, rhs in
            overlapPrecedes(lhs, rhs)
        }
        var overlaps: [OverlapAnalyticsPoint] = []
        var cursor = events.first?.date
        var index = events.startIndex

        while index < events.endIndex {
            let date = events[index].date
            if let start = cursor, date > start, activeIDs.count > 1 {
                let pair = firstTwoActiveOverlaps(heap: &activeHeap, activeIDs: activeIDs)
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
                activeIDs.remove(events[index].segmentID)
                index = events.index(after: index)
            }
            while index < events.endIndex, events[index].date == date, events[index].isStart == true {
                if let bounded = boundedByID[events[index].segmentID] {
                    activeIDs.insert(events[index].segmentID)
                    activeHeap.insert(bounded)
                }
                index = events.index(after: index)
            }
            cursor = date
        }

        return overlaps.sorted { $0.durationSeconds > $1.durationSeconds }
    }

    private func firstTwoActiveOverlaps(
        heap: inout OverlapMinHeap,
        activeIDs: Set<UUID>
    ) -> (first: BoundedOverlapSegment?, second: BoundedOverlapSegment?) {
        heap.removeInactive(activeIDs: activeIDs)
        guard let first = heap.popMin() else { return (nil, nil) }
        heap.removeInactive(activeIDs: activeIDs)
        let second = heap.min
        heap.insert(first)
        return (first, second)
    }

    private func overlapPrecedes(_ lhs: BoundedOverlapSegment, _ rhs: BoundedOverlapSegment) -> Bool {
        if lhs.interval.start == rhs.interval.start {
            if lhs.title == rhs.title {
                return lhs.segment.id.uuidString < rhs.segment.id.uuidString
            }
            return lhs.title < rhs.title
        }
        return lhs.interval.start < rhs.interval.start
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
    let interval: DateInterval
    let title: String
}

private struct OverlapMinHeap {
    private var elements: [BoundedOverlapSegment] = []
    private let sort: (BoundedOverlapSegment, BoundedOverlapSegment) -> Bool

    init(sort: @escaping (BoundedOverlapSegment, BoundedOverlapSegment) -> Bool) {
        self.sort = sort
    }

    var min: BoundedOverlapSegment? {
        elements.first
    }

    mutating func insert(_ element: BoundedOverlapSegment) {
        elements.append(element)
        siftUp(from: elements.count - 1)
    }

    mutating func popMin() -> BoundedOverlapSegment? {
        guard !elements.isEmpty else { return nil }
        if elements.count == 1 {
            return elements.removeLast()
        }

        let min = elements[0]
        elements[0] = elements.removeLast()
        siftDown(from: 0)
        return min
    }

    mutating func removeInactive(activeIDs: Set<UUID>) {
        while let candidate = min, !activeIDs.contains(candidate.segment.id) {
            _ = popMin()
        }
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        var parent = parentIndex(of: child)

        while child > 0, sort(elements[child], elements[parent]) {
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

            if left < elements.count, sort(elements[left], elements[candidate]) {
                candidate = left
            }
            if right < elements.count, sort(elements[right], elements[candidate]) {
                candidate = right
            }
            guard candidate != parent else { return }

            elements.swapAt(parent, candidate)
            parent = candidate
        }
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
