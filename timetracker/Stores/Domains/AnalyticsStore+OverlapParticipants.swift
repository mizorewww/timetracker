import Foundation

extension AnalyticsStore {
    func overlapParticipants(
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

    func firstActiveParticipants(
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
}

struct OverlapParticipantMinHeap {
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
