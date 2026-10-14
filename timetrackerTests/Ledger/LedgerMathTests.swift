import Foundation
import SwiftData
import Testing
@testable import timetracker

/// Hand-computed answers for the numbers users read: gross is the sum of
/// segments, wall is their union, overlap is gross − wall (AD-001).
@MainActor
struct LedgerMathTests {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let service = TimeAggregationService()

    private func segment(
        from start: TimeInterval,
        to end: TimeInterval?,
        deleted: Bool = false
    ) -> TimeSegment {
        let segment = TimeSegment(
            sessionID: UUID(),
            taskID: UUID(),
            source: .timer,
            deviceID: "test",
            startedAt: base.addingTimeInterval(start),
            endedAt: end.map { base.addingTimeInterval($0) }
        )
        if deleted {
            segment.deletedAt = base
        }
        return segment
    }

    @Test
    func overlappingParallelTimersSplitIntoGrossWallAndOverlap() {
        let now = base.addingTimeInterval(86400)
        let segments = [
            segment(from: 0, to: 3600),
            segment(from: 1800, to: 5400),
            segment(from: 7200, to: 7800),
        ]

        let gross = service.grossSeconds(segments, now: now)
        let wall = service.wallClockSeconds(segments, now: now)

        #expect(gross == 3600 + 3600 + 600)
        #expect(wall == 5400 + 600)
        #expect(gross - wall == 1800)
    }

    @Test
    func deletedSegmentsCountForNothingAndRunningOnesCountUntilNow() {
        let now = base.addingTimeInterval(1000)
        let segments = [
            segment(from: 0, to: 600, deleted: true),
            segment(from: 400, to: nil),
            // An end recorded past `now` (clock skew) is clamped to now.
            segment(from: 900, to: 5000),
            // A start in the future contributes nothing yet.
            segment(from: 2000, to: 3000),
        ]

        #expect(service.grossSeconds(segments, now: now) == 600 + 100)
        #expect(service.wallClockSeconds(segments, now: now) == 600)
    }

    @Test(arguments: ["UTC", "America/New_York"])
    func secondsByDaySplitsAtLocalMidnight(timeZoneID: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: timeZoneID))
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10)))
        let interval = DateInterval(
            start: midnight.addingTimeInterval(-1800),
            end: midnight.addingTimeInterval(2700)
        )

        let totals = service.secondsByDay(intervals: [interval], calendar: calendar)

        #expect(totals[midnight.addingTimeInterval(-86400)] == 1800)
        #expect(totals[midnight] == 2700)
    }

    @Test
    func daylightSavingDayHasTwentyThreeHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let springForward = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: springForward))

        let totals = service.secondsByDay(
            intervals: [DateInterval(start: springForward, end: nextDay)],
            calendar: calendar
        )

        #expect(totals == [springForward: 23 * 3600])
    }

    @Test
    func stopThenImmediateRestartContinuesTheSameTimer() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test")
            .createTask(title: "Rapid restart", parentID: nil)
        let handler = makeTestSystemActionCommandHandler()

        let started = try handler.startTimerMutation(taskID: task.id, container: context.container)
        let firstID = try #require(started.subjectSegmentID)
        _ = try handler.stopTimerMutation(segmentID: firstID, container: context.container)
        let restarted = try handler.startTimerMutation(taskID: task.id, container: context.container)

        let readContext = ModelContext(context.container)
        let active = try SwiftDataTimeTrackingRepository(context: readContext).activeSegments()
        let original = try #require(
            readContext.fetch(FetchDescriptor<TimeSegment>(predicate: #Predicate { $0.id == firstID })).first
        )
        #expect(active.count == 1)
        #expect(restarted.subjectSegmentID == TimerRapidRestartPolicy().replacementSegmentID(predecessorSegmentID: firstID))
        #expect(active.first?.startedAt == original.startedAt)
        #expect(active.first?.sessionID == original.sessionID)
        #expect(original.deletedAt != nil)
    }

    @Test
    func manualRecordsAndLongGapsAreNeverCoalesced() {
        let policy = TimerRapidRestartPolicy()
        let taskID = UUID()
        let start = base
        let end = base.addingTimeInterval(600)

        #expect(policy.shouldCoalesce(
            previousTaskID: taskID, previousSource: .timer,
            previousStartedAt: start, previousEndedAt: end,
            nextTaskID: taskID, nextSource: .timer,
            nextStartedAt: end.addingTimeInterval(59)
        ))
        #expect(policy.shouldCoalesce(
            previousTaskID: taskID, previousSource: .timer,
            previousStartedAt: start, previousEndedAt: end,
            nextTaskID: taskID, nextSource: .timer,
            nextStartedAt: end.addingTimeInterval(60)
        ) == false)
        #expect(policy.shouldCoalesce(
            previousTaskID: taskID, previousSource: .manual,
            previousStartedAt: start, previousEndedAt: end,
            nextTaskID: taskID, nextSource: .timer,
            nextStartedAt: end.addingTimeInterval(1)
        ) == false)
        #expect(policy.shouldCoalesce(
            previousTaskID: taskID, previousSource: .timer,
            previousStartedAt: start, previousEndedAt: end,
            nextTaskID: UUID(), nextSource: .timer,
            nextStartedAt: end.addingTimeInterval(1)
        ) == false)
    }
}
