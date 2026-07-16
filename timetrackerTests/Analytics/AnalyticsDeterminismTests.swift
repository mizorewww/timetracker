import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct AnalyticsDeterminismTests {
    @Test
    func equalDurationTasksUseStableRankingAcrossInputPermutations() {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let alpha = TaskNode(title: "Alpha", parentID: nil, deviceID: "test")
        let zulu = TaskNode(title: "Zulu", parentID: nil, deviceID: "test")
        let alphaSegment = segment(taskID: alpha.id, start: start)
        let zuluSegment = segment(taskID: zulu.id, start: start)
        let alphaItem = bounded(alphaSegment)
        let zuluItem = bounded(zuluSegment)
        let store = AnalyticsStore()

        let forward = store.taskBreakdown(
            items: [zuluItem, alphaItem],
            tasks: [zulu, alpha],
            sessions: [],
            taskPathByID: [alpha.id: alpha.title, zulu.id: zulu.title]
        )
        let reversed = store.taskBreakdown(
            items: [alphaItem, zuluItem],
            tasks: [alpha, zulu],
            sessions: [],
            taskPathByID: [alpha.id: alpha.title, zulu.id: zulu.title]
        )

        #expect(forward.map(\.taskID) == [alpha.id, zulu.id])
        #expect(reversed.map(\.taskID) == forward.map(\.taskID))
    }

    @Test
    func equalPeakHoursUseTheEarliestLocalHour() {
        let first = AnalyticsSelectionPolicy.peakHour(in: [14: 3_600, 9: 3_600])
        let second = AnalyticsSelectionPolicy.peakHour(in: [9: 3_600, 14: 3_600])

        #expect(first?.hour == 9)
        #expect(first?.seconds == 3_600)
        #expect(second?.hour == first?.hour)
        #expect(second?.seconds == first?.seconds)
    }

    @Test
    func deletedTaskFallbackUsesLatestSessionRegardlessOfInputOrder() {
        let taskID = UUID()
        let older = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "old",
            startedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            titleSnapshot: "Older title"
        )
        let newer = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "new",
            startedAt: Date(timeIntervalSinceReferenceDate: 2_000),
            titleSnapshot: "Latest title"
        )
        let item = bounded(
            segment(
                taskID: taskID,
                sessionID: newer.id,
                start: Date(timeIntervalSinceReferenceDate: 3_000)
            )
        )
        let store = AnalyticsStore()

        let forward = store.taskBreakdown(
            items: [item],
            tasks: [],
            sessions: [older, newer],
            taskPathByID: [:]
        )
        let reversed = store.taskBreakdown(
            items: [item],
            tasks: [],
            sessions: [newer, older],
            taskPathByID: [:]
        )
        let participants = store.overlapParticipants(
            taskIDs: [taskID],
            tasks: [],
            sessions: [newer, older]
        )

        #expect(forward.first?.title == "Latest title")
        #expect(reversed.first?.title == "Latest title")
        #expect(participants[taskID]?.title == "Latest title")
    }

    private func segment(
        taskID: UUID,
        sessionID: UUID = UUID(),
        start: Date
    ) -> TimeSegment {
        TimeSegment(
            sessionID: sessionID,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600)
        )
    }

    private func bounded(_ segment: TimeSegment) -> AnalyticsBoundedSegment {
        AnalyticsBoundedSegment(
            segment: segment,
            interval: DateInterval(
                start: segment.startedAt,
                end: segment.endedAt ?? segment.startedAt
            )
        )
    }
}
