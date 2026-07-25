import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct AnalyticsVisualSnapshotServiceTests {
    @Test @MainActor
    func sendableVisualSnapshotMatchesExistingTodayReadModels() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 12))
        )
        let day = calendar.startOfDay(for: now)
        let design = TaskNode(
            title: "Design",
            parentID: nil,
            deviceID: "test",
            colorHex: "0A84FF",
            iconName: "paintbrush"
        )
        let review = TaskNode(
            title: "Review",
            parentID: nil,
            deviceID: "test",
            colorHex: "FF9F0A",
            iconName: "doc.text"
        )
        let designSession = TimeSession(
            taskID: design.id,
            source: .timer,
            deviceID: "test",
            startedAt: day.addingTimeInterval(8 * 3600),
            titleSnapshot: design.title
        )
        let reviewSession = TimeSession(
            taskID: review.id,
            source: .timer,
            deviceID: "test",
            startedAt: day.addingTimeInterval(9 * 3600),
            titleSnapshot: review.title
        )
        let segments = [
            TimeSegment(
                sessionID: designSession.id,
                taskID: design.id,
                source: .timer,
                deviceID: "test",
                startedAt: day.addingTimeInterval(8 * 3600 + 30 * 60),
                endedAt: day.addingTimeInterval(10 * 3600)
            ),
            TimeSegment(
                sessionID: reviewSession.id,
                taskID: review.id,
                source: .timer,
                deviceID: "test",
                startedAt: day.addingTimeInterval(9 * 3600 + 15 * 60),
                endedAt: day.addingTimeInterval(11 * 3600)
            ),
        ]
        let period = try #require(calendar.dateInterval(of: .day, for: now))
        let tasks = [design, review]
        let sessions = [designSession, reviewSession]
        let input = AnalyticsVisualSnapshotInput(
            range: .today,
            period: period,
            evaluatedAt: now,
            calendar: calendar,
            segments: segments,
            tasks: tasks,
            sessions: sessions,
            taskParentPathByID: [:]
        )

        let actual = AnalyticsVisualSnapshotService().snapshot(input)
        let expectedActivity = HourTaskActivityService().hourlyActivity(
            segments: segments,
            tasks: tasks,
            sessions: sessions,
            date: period.start,
            now: now,
            calendar: calendar
        )
        let expectedTimeline = AnalyticsTimelineSnapshotService().snapshot(
            segments: segments,
            tasks: tasks,
            sessions: sessions,
            taskParentPathByID: [:],
            date: period.start,
            now: now,
            calendar: calendar
        )
        let expectedOverlap = AnalyticsStore().overlapSegments(
            items: AnalyticsStore().boundedSegments(segments, in: period, now: now),
            tasks: tasks,
            sessions: sessions
        )

        #expect(actual.todayActivity == expectedActivity)
        #expect(actual.timeline == expectedTimeline)
        #expect(actual.overlaps == expectedOverlap)
    }

    @Test @MainActor
    func detachedVisualSnapshotReturnsTheSameProjectedValue() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 12))
        )
        let period = try #require(calendar.dateInterval(of: .day, for: now))
        let task = TaskNode(title: "Write", parentID: nil, deviceID: "test")
        let session = TimeSession(
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-3600),
            titleSnapshot: task.title
        )
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now.addingTimeInterval(-1800)
        )
        let input = AnalyticsVisualSnapshotInput(
            range: .today,
            period: period,
            evaluatedAt: now,
            calendar: calendar,
            segments: [segment],
            tasks: [task],
            sessions: [session],
            taskParentPathByID: [:]
        )

        let expected = AnalyticsVisualSnapshotService().snapshot(input)
        let actual = await AnalyticsVisualSnapshotTask.resolve(input)

        #expect(actual == expected)
    }

    @Test @MainActor
    func todayWithoutSegmentsKeepsTheExistingTwentyFourHourActivityShape() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 17, hour: 12))
        )
        let period = try #require(calendar.dateInterval(of: .day, for: now))
        let input = AnalyticsVisualSnapshotInput(
            range: .today,
            period: period,
            evaluatedAt: now,
            calendar: calendar,
            segments: [],
            tasks: [],
            sessions: [],
            taskParentPathByID: [:]
        )

        let snapshot = AnalyticsVisualSnapshotService().snapshot(input)

        #expect(snapshot.todayActivity.count == 24)
        #expect(snapshot.todayActivity.allSatisfy { $0.slices.isEmpty })
        #expect(snapshot.timeline == .empty)
        #expect(snapshot.overlaps.isEmpty)
    }
}
