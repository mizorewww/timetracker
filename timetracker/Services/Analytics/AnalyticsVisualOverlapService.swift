import Foundation

nonisolated struct AnalyticsVisualOverlapService {
    func overlaps(
        _ segments: [AnalyticsVisualBoundedSegment],
        input: AnalyticsVisualSnapshotInput
    ) -> [OverlapAnalyticsPoint] {
        guard segments.count > 1, Task.isCancelled == false else { return [] }
        let participantsByTaskID = Set(segments.map(\.taskID)).reduce(into: [UUID: OverlapAnalyticsParticipant]()) {
            result,
            taskID in
            result[taskID] = OverlapAnalyticsParticipant(
                id: taskID,
                title: input.taskByID[taskID]?.title
                    ?? input.overlapFallbackTitleByTaskID[taskID]
                    ?? input.unavailableTaskTitle
            )
        }
        let rawWindows = sweepOverlapWindows(segments, participantsByTaskID: participantsByTaskID)
        guard Task.isCancelled == false else { return [] }
        let gross = segments.reduce(0) { $0 + $1.durationSeconds }
        let wall = mergedIntervals(segments.map(\.interval)).reduce(0) {
            $0 + max(0, Int($1.end.timeIntervalSince($1.start)))
        }
        return materializeOverlapWindows(
            rawWindows,
            expectedExcessSeconds: max(0, gross - wall)
        )
    }
}
