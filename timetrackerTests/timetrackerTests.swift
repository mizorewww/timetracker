import Foundation
import Testing
@testable import timetracker

struct TimeTrackerTests {
    @Test @MainActor
    func grossAndWallClockAggregationHandleOverlaps() {
        let taskID = UUID()
        let sessionA = UUID()
        let sessionB = UUID()
        let start = Date(timeIntervalSince1970: 1000)

        let first = TimeSegment(
            sessionID: sessionA,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(60 * 60)
        )

        let second = TimeSegment(
            sessionID: sessionB,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start.addingTimeInterval(30 * 60),
            endedAt: start.addingTimeInterval(90 * 60)
        )

        let service = TimeAggregationService()

        #expect(service.totalSeconds(segments: [first, second], mode: .gross) == 7_200)
        #expect(service.totalSeconds(segments: [first, second], mode: .wallClock) == 5_400)
    }

    @Test
    func durationFormattingUsesCompactClockText() {
        #expect(DurationFormatter.compact(4 * 3600 + 35 * 60) == "4h 35m")
        #expect(DurationFormatter.clock(84) == "01:24")
    }
}
