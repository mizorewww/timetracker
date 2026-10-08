import Foundation
import HeapModule

extension AnalyticsStore {
    func overlapParticipants(
        taskIDs: Set<UUID>,
        tasks: [TaskNode],
        sessions: [TimeSession]
    ) -> [UUID: OverlapAnalyticsParticipant] {
        let taskByID = tasks.latestByID()
        let fallbackTitleByTaskID = AnalyticsSelectionPolicy.latestSessionTitleByTaskID(
            sessions: sessions,
            restrictingTo: taskIDs
        )

        return taskIDs.reduce(into: [UUID: OverlapAnalyticsParticipant]()) { result, taskID in
            let title = taskByID[taskID]?.title
                ?? fallbackTitleByTaskID[taskID]
                ?? AppStrings.localized("task.unavailable")
            result[taskID] = OverlapAnalyticsParticipant(id: taskID, title: title)
        }
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
