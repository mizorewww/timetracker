import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreAnalyticsStoreTests {
    @Test
    func recentRecordsUseTheMatchingSessionTitleSnapshot() throws {
        let taskID = UUID()
        let oldSession = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: Date(timeIntervalSince1970: 100),
            titleSnapshot: "Old title"
        )
        let newSession = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: Date(timeIntervalSince1970: 300),
            titleSnapshot: "New title"
        )
        let segments = [oldSession, newSession].map { session in
            TimeSegment(
                sessionID: session.id,
                taskID: taskID,
                source: .timer,
                deviceID: "test",
                startedAt: session.startedAt,
                endedAt: session.startedAt.addingTimeInterval(60)
            )
        }

        let records = AnalyticsStore().recentRecords(
            segments: segments,
            sessions: [oldSession, newSession],
            tasks: [],
            taskIDs: [taskID],
            taskPathByID: [:],
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(records.map(\.title) == ["New title", "Old title"])
    }

    @Test @MainActor
    func analyticsSnapshotCompactsDenseOverlapsWithSweepLine() {
        let start = Date(timeIntervalSince1970: 10_000)
        let tasks = (0..<5).map { index in
            TaskNode(
                title: "Task \(index)",
                parentID: nil,
                deviceID: "test",
                colorHex: nil,
                iconName: nil
            )
        }
        let sessions = tasks.map { task in
            TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: start, titleSnapshot: task.title)
        }
        let segments = zip(tasks, sessions).map { task, session in
            TimeSegment(
                sessionID: session.id,
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                endedAt: start.addingTimeInterval(3_600)
            )
        }

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: tasks,
            segments: segments,
            sessions: sessions,
            taskPathByID: [:],
            taskParentPathByID: [:],
            now: start.addingTimeInterval(3_600)
        )

        #expect(snapshot.overview.grossSeconds == 18_000)
        #expect(snapshot.overview.wallSeconds == 3_600)
        #expect(snapshot.overview.overlapSeconds == 14_400)
        #expect(snapshot.overlaps.count == 1)
        #expect(snapshot.overlaps.first?.wallDurationSeconds == 3_600)
        #expect(snapshot.overlaps.first?.excessDurationSeconds == 14_400)
        #expect(snapshot.overlaps.first?.concurrentSegmentCount == 5)
        #expect(snapshot.overlaps.first?.participantCount == 5)
        #expect(snapshot.overlaps.first?.visibleParticipants.count == 3)
        #expect(snapshot.overlaps.first?.hiddenParticipantCount == 2)
        #expect(snapshot.overlaps.reduce(0) { $0 + $1.excessDurationSeconds } == snapshot.overview.overlapSeconds)
    }

    @Test @MainActor
    func analyticsOverlapWindowsConserveStaggeredTripleConcurrency() {
        let start = Date(timeIntervalSince1970: 20_000)
        let tasks = ["Alpha", "Beta", "Gamma"].map {
            TaskNode(title: $0, parentID: nil, deviceID: "test")
        }
        let sessions = tasks.map { task in
            TimeSession(
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                titleSnapshot: task.title
            )
        }
        let segments = [
            TimeSegment(
                sessionID: sessions[0].id,
                taskID: tasks[0].id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                endedAt: start.addingTimeInterval(40 * 60)
            ),
            TimeSegment(
                sessionID: sessions[1].id,
                taskID: tasks[1].id,
                source: .timer,
                deviceID: "test",
                startedAt: start.addingTimeInterval(10 * 60),
                endedAt: start.addingTimeInterval(50 * 60)
            ),
            TimeSegment(
                sessionID: sessions[2].id,
                taskID: tasks[2].id,
                source: .timer,
                deviceID: "test",
                startedAt: start.addingTimeInterval(20 * 60),
                endedAt: start.addingTimeInterval(30 * 60)
            )
        ]

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: tasks,
            segments: Array(segments.reversed()),
            sessions: Array(sessions.reversed()),
            taskPathByID: [:],
            taskParentPathByID: [:],
            now: start.addingTimeInterval(60 * 60)
        )

        #expect(snapshot.overview.grossSeconds == 90 * 60)
        #expect(snapshot.overview.wallSeconds == 50 * 60)
        #expect(snapshot.overview.overlapSeconds == 40 * 60)
        #expect(snapshot.overlaps.reduce(0) { $0 + $1.excessDurationSeconds } == 40 * 60)
        #expect(snapshot.overlaps.count == 3)

        let triple = snapshot.overlaps.first { $0.concurrentSegmentCount == 3 }
        #expect(triple?.wallDurationSeconds == 10 * 60)
        #expect(triple?.excessDurationSeconds == 20 * 60)
        #expect(triple?.participantCount == 3)
        #expect(triple?.visibleParticipants.map(\.id) == tasks.map(\.id))
        #expect(triple?.visibleParticipants.map(\.title) == ["Alpha", "Beta", "Gamma"])

        let pairWindows = snapshot.overlaps.filter { $0.concurrentSegmentCount == 2 }
        #expect(pairWindows.map(\.start) == [
            start.addingTimeInterval(10 * 60),
            start.addingTimeInterval(30 * 60)
        ])
        #expect(pairWindows.allSatisfy { $0.excessDurationSeconds == 10 * 60 })
    }

    @Test @MainActor
    func analyticsOverlapMergesAdjacentReplacementSegmentsWithoutCrossingBoundaryOnlyRecords() {
        let start = Date(timeIntervalSince1970: 30_000)
        let firstTask = TaskNode(title: "Alpha", parentID: nil, deviceID: "test")
        let secondTask = TaskNode(title: "Beta", parentID: nil, deviceID: "test")
        let boundaryTask = TaskNode(title: "Boundary", parentID: nil, deviceID: "test")
        let firstSession = TimeSession(taskID: firstTask.id, source: .timer, deviceID: "test", startedAt: start)
        let secondSession = TimeSession(taskID: secondTask.id, source: .timer, deviceID: "test", startedAt: start)
        let boundarySession = TimeSession(taskID: boundaryTask.id, source: .manual, deviceID: "test", startedAt: start)
        let segments = [
            TimeSegment(
                sessionID: firstSession.id,
                taskID: firstTask.id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                endedAt: start.addingTimeInterval(20 * 60)
            ),
            TimeSegment(
                sessionID: secondSession.id,
                taskID: secondTask.id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                endedAt: start.addingTimeInterval(10 * 60)
            ),
            TimeSegment(
                sessionID: secondSession.id,
                taskID: secondTask.id,
                source: .timer,
                deviceID: "test",
                startedAt: start.addingTimeInterval(10 * 60),
                endedAt: start.addingTimeInterval(20 * 60)
            ),
            TimeSegment(
                sessionID: boundarySession.id,
                taskID: boundaryTask.id,
                source: .manual,
                deviceID: "test",
                startedAt: start.addingTimeInterval(20 * 60),
                endedAt: start.addingTimeInterval(30 * 60)
            ),
            TimeSegment(
                sessionID: boundarySession.id,
                taskID: boundaryTask.id,
                source: .manual,
                deviceID: "test",
                startedAt: start.addingTimeInterval(5 * 60),
                endedAt: start.addingTimeInterval(5 * 60)
            ),
            TimeSegment(
                sessionID: boundarySession.id,
                taskID: boundaryTask.id,
                source: .manual,
                deviceID: "test",
                startedAt: start.addingTimeInterval(6 * 60),
                endedAt: start.addingTimeInterval(5 * 60)
            )
        ]

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [firstTask, secondTask, boundaryTask],
            segments: segments,
            sessions: [firstSession, secondSession, boundarySession],
            taskPathByID: [:],
            taskParentPathByID: [:],
            now: start.addingTimeInterval(40 * 60)
        )

        #expect(snapshot.overview.grossSeconds == 50 * 60)
        #expect(snapshot.overview.wallSeconds == 30 * 60)
        #expect(snapshot.overview.overlapSeconds == 20 * 60)
        #expect(snapshot.overlaps.count == 1)
        #expect(snapshot.overlaps.first?.start == start)
        #expect(snapshot.overlaps.first?.end == start.addingTimeInterval(20 * 60))
        #expect(snapshot.overlaps.first?.wallDurationSeconds == 20 * 60)
        #expect(snapshot.overlaps.first?.excessDurationSeconds == 20 * 60)
        #expect(
            Set(snapshot.overlaps.first?.visibleParticipants.map(\.id) ?? [])
                == Set([firstTask.id, secondTask.id])
        )
    }

    @Test @MainActor
    func analyticsOverlapDoesNotMergeHiddenParticipantReplacement() {
        let start = Date(timeIntervalSince1970: 32_000)
        let tasks = ["Alpha", "Beta", "Gamma", "Zulu Before", "Zulu After"].map {
            TaskNode(title: $0, parentID: nil, deviceID: "test")
        }
        let sessions = tasks.map { task in
            TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: start)
        }
        let steadySegments = (0..<3).map { index in
            TimeSegment(
                sessionID: sessions[index].id,
                taskID: tasks[index].id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                endedAt: start.addingTimeInterval(20 * 60)
            )
        }
        let replacingSegments = [
            TimeSegment(
                sessionID: sessions[3].id,
                taskID: tasks[3].id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                endedAt: start.addingTimeInterval(10 * 60)
            ),
            TimeSegment(
                sessionID: sessions[4].id,
                taskID: tasks[4].id,
                source: .timer,
                deviceID: "test",
                startedAt: start.addingTimeInterval(10 * 60),
                endedAt: start.addingTimeInterval(20 * 60)
            )
        ]

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: tasks,
            segments: steadySegments + replacingSegments,
            sessions: sessions,
            taskPathByID: [:],
            taskParentPathByID: [:],
            now: start.addingTimeInterval(30 * 60)
        )

        #expect(snapshot.overview.overlapSeconds == 60 * 60)
        #expect(snapshot.overlaps.count == 2)
        #expect(snapshot.overlaps.map(\.start) == [start, start.addingTimeInterval(10 * 60)])
        #expect(snapshot.overlaps.allSatisfy { $0.concurrentSegmentCount == 4 })
        #expect(snapshot.overlaps.allSatisfy { $0.participantCount == 4 })
        #expect(snapshot.overlaps.allSatisfy {
            $0.visibleParticipants.map(\.title) == ["Alpha", "Beta", "Gamma"]
        })
        #expect(snapshot.overlaps.reduce(0) { $0 + $1.excessDurationSeconds } == 60 * 60)
    }

    @Test @MainActor
    func analyticsOverlapCountsSegmentsAndUsesTaskIDsForParticipants() {
        let start = Date(timeIntervalSince1970: 35_000)
        let repeatedTask = TaskNode(title: "Repeated", parentID: nil, deviceID: "test")
        let otherTask = TaskNode(title: "Repeated", parentID: nil, deviceID: "test")
        let repeatedSession = TimeSession(taskID: repeatedTask.id, source: .timer, deviceID: "test", startedAt: start)
        let otherSession = TimeSession(taskID: otherTask.id, source: .timer, deviceID: "test", startedAt: start)
        let segments = [
            TimeSegment(
                sessionID: repeatedSession.id,
                taskID: repeatedTask.id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                endedAt: start.addingTimeInterval(10 * 60)
            ),
            TimeSegment(
                sessionID: repeatedSession.id,
                taskID: repeatedTask.id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                endedAt: start.addingTimeInterval(10 * 60)
            ),
            TimeSegment(
                sessionID: otherSession.id,
                taskID: otherTask.id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                endedAt: start.addingTimeInterval(10 * 60)
            )
        ]

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [repeatedTask, otherTask],
            segments: segments,
            sessions: [repeatedSession, otherSession],
            taskPathByID: [:],
            taskParentPathByID: [:],
            now: start.addingTimeInterval(20 * 60)
        )

        #expect(snapshot.overview.overlapSeconds == 20 * 60)
        #expect(snapshot.overlaps.first?.concurrentSegmentCount == 3)
        #expect(snapshot.overlaps.first?.participantCount == 2)
        #expect(
            Set(snapshot.overlaps.first?.visibleParticipants.map(\.id) ?? [])
                == Set([repeatedTask.id, otherTask.id])
        )
        #expect(snapshot.overlaps.first?.excessDurationSeconds == 20 * 60)
    }

    @Test @MainActor
    func analyticsOverlapConservesCrossMidnightSpringForwardIntervals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        func date(day: Int, hour: Int, minute: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 3,
                day: day,
                hour: hour,
                minute: minute
            )))
        }

        let tasks = ["Alpha", "Beta", "Gamma"].map {
            TaskNode(title: $0, parentID: nil, deviceID: "test")
        }
        let sessionStart = try date(day: 7, hour: 23, minute: 30)
        let sessions = tasks.map { task in
            TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: sessionStart)
        }
        let segments = [
            TimeSegment(
                sessionID: sessions[0].id,
                taskID: tasks[0].id,
                source: .timer,
                deviceID: "test",
                startedAt: try date(day: 7, hour: 23, minute: 30),
                endedAt: try date(day: 8, hour: 4)
            ),
            TimeSegment(
                sessionID: sessions[1].id,
                taskID: tasks[1].id,
                source: .timer,
                deviceID: "test",
                startedAt: try date(day: 8, hour: 0, minute: 30),
                endedAt: try date(day: 8, hour: 3, minute: 30)
            ),
            TimeSegment(
                sessionID: sessions[2].id,
                taskID: tasks[2].id,
                source: .timer,
                deviceID: "test",
                startedAt: try date(day: 8, hour: 1, minute: 30),
                endedAt: try date(day: 8, hour: 4, minute: 30)
            )
        ]
        let now = try date(day: 8, hour: 12)
        let startOfDay = try date(day: 8, hour: 0)

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: tasks,
            segments: segments,
            sessions: sessions,
            taskPathByID: [:],
            taskParentPathByID: [:],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.overview.grossSeconds == 7 * 3_600)
        #expect(snapshot.overview.wallSeconds == 3 * 3_600 + 30 * 60)
        #expect(snapshot.overview.overlapSeconds == 3 * 3_600 + 30 * 60)
        #expect(snapshot.overlaps.reduce(0) { $0 + $1.excessDurationSeconds } == snapshot.overview.overlapSeconds)
        #expect(snapshot.overlaps.contains { $0.start == startOfDay.addingTimeInterval(30 * 60) })

        let triple = try #require(snapshot.overlaps.first { $0.concurrentSegmentCount == 3 })
        #expect(triple.wallDurationSeconds == 3_600)
        #expect(triple.excessDurationSeconds == 2 * 3_600)
    }

    @Test @MainActor
    func analyticsOverlapConservesCrossMidnightFallBackIntervals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let formatter = ISO8601DateFormatter()
        func date(_ value: String) throws -> Date {
            try #require(formatter.date(from: value))
        }

        let tasks = ["Alpha", "Beta", "Gamma"].map {
            TaskNode(title: $0, parentID: nil, deviceID: "test")
        }
        let sessionStart = try date("2026-10-31T23:30:00-07:00")
        let sessions = tasks.map { task in
            TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: sessionStart)
        }
        let segments = [
            TimeSegment(
                sessionID: sessions[0].id,
                taskID: tasks[0].id,
                source: .timer,
                deviceID: "test",
                startedAt: sessionStart,
                endedAt: try date("2026-11-01T04:00:00-08:00")
            ),
            TimeSegment(
                sessionID: sessions[1].id,
                taskID: tasks[1].id,
                source: .timer,
                deviceID: "test",
                startedAt: try date("2026-11-01T00:30:00-07:00"),
                endedAt: try date("2026-11-01T02:30:00-08:00")
            ),
            TimeSegment(
                sessionID: sessions[2].id,
                taskID: tasks[2].id,
                source: .timer,
                deviceID: "test",
                startedAt: try date("2026-11-01T01:30:00-07:00"),
                endedAt: try date("2026-11-01T03:30:00-08:00")
            )
        ]
        let now = try date("2026-11-01T12:00:00-08:00")
        let startOfDay = try date("2026-11-01T00:00:00-07:00")

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: tasks,
            segments: segments,
            sessions: sessions,
            taskPathByID: [:],
            taskParentPathByID: [:],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.overview.grossSeconds == 11 * 3_600)
        #expect(snapshot.overview.wallSeconds == 5 * 3_600)
        #expect(snapshot.overview.overlapSeconds == 6 * 3_600)
        #expect(snapshot.overlaps.reduce(0) { $0 + $1.excessDurationSeconds } == 6 * 3_600)
        #expect(snapshot.overlaps.contains { $0.start == startOfDay.addingTimeInterval(30 * 60) })

        let triple = try #require(snapshot.overlaps.first { $0.concurrentSegmentCount == 3 })
        #expect(triple.wallDurationSeconds == 2 * 3_600)
        #expect(triple.excessDurationSeconds == 4 * 3_600)
    }

    @Test @MainActor
    func analyticsOverlapAllocatesSubsecondRemaindersToMatchGrossMinusWall() {
        let start = Date(timeIntervalSince1970: 40_000)
        let tasks = ["Alpha", "Beta", "Gamma"].map {
            TaskNode(title: $0, parentID: nil, deviceID: "test")
        }
        let sessions = tasks.map { task in
            TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: start)
        }
        let segments = tasks.indices.map { index in
            TimeSegment(
                sessionID: sessions[index].id,
                taskID: tasks[index].id,
                source: .timer,
                deviceID: "test",
                startedAt: start.addingTimeInterval(Double(index) * 0.25),
                endedAt: start.addingTimeInterval(2.25 + Double(index) * 0.25)
            )
        }

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: tasks,
            segments: segments,
            sessions: sessions,
            taskPathByID: [:],
            taskParentPathByID: [:],
            now: start.addingTimeInterval(3)
        )

        #expect(snapshot.overview.grossSeconds == 6)
        #expect(snapshot.overview.wallSeconds == 2)
        #expect(snapshot.overview.overlapSeconds == 4)
        #expect(snapshot.overlaps.reduce(0) { $0 + $1.excessDurationSeconds } == 4)
    }

    @Test
    func analyticsOverlapPresentationReportsEveryHiddenExcessSecond() {
        let start = Date(timeIntervalSince1970: 50_000)
        let participant = OverlapAnalyticsParticipant(id: UUID(), title: "Task")
        let windows = (0..<8).map { index in
            OverlapAnalyticsPoint(
                start: start.addingTimeInterval(Double(index) * 60),
                end: start.addingTimeInterval(Double(index + 1) * 60),
                concurrentSegmentCount: 2,
                participantCount: 1,
                visibleParticipants: [participant],
                wallDurationSeconds: 60,
                excessDurationSeconds: (index + 1) * 10
            )
        }

        let presentation = AnalyticsOverlapPresentation(
            overlaps: windows,
            maximumVisibleWindows: 6
        )

        #expect(presentation.visibleWindows.count == 6)
        #expect(presentation.hiddenWindowCount == 2)
        #expect(presentation.hiddenExcessSeconds == 150)
        #expect(
            presentation.visibleWindows.reduce(0) { $0 + $1.excessDurationSeconds }
                + presentation.hiddenExcessSeconds
                == windows.reduce(0) { $0 + $1.excessDurationSeconds }
        )
    }

    @Test @MainActor
    func analyticsGlobalStatisticsClipSegmentsToTheSelectedRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 12)))
        let startOfDay = calendar.startOfDay(for: now)
        let firstTask = TaskNode(title: "First", parentID: nil, deviceID: "test")
        let secondTask = TaskNode(title: "Second", parentID: nil, deviceID: "test")
        let firstSession = TimeSession(taskID: firstTask.id, source: .timer, deviceID: "test", startedAt: startOfDay.addingTimeInterval(-1_800))
        let secondSession = TimeSession(taskID: secondTask.id, source: .timer, deviceID: "test", startedAt: startOfDay.addingTimeInterval(-900))
        let segments = [
            TimeSegment(
                sessionID: firstSession.id,
                taskID: firstTask.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(-1_800),
                endedAt: startOfDay.addingTimeInterval(1_800)
            ),
            TimeSegment(
                sessionID: secondSession.id,
                taskID: secondTask.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(-900),
                endedAt: startOfDay.addingTimeInterval(900)
            )
        ]

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [firstTask, secondTask],
            segments: segments,
            sessions: [firstSession, secondSession],
            taskPathByID: [firstTask.id: firstTask.title, secondTask.id: secondTask.title],
            taskParentPathByID: [:],
            now: now,
            calendar: calendar
        )
        let engineOverview = AnalyticsEngine().overview(
            segments: segments,
            range: .today,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.overview.grossSeconds == 2_700)
        #expect(snapshot.overview.wallSeconds == 1_800)
        #expect(snapshot.overview.overlapSeconds == 900)
        #expect(snapshot.daily.reduce(0) { $0 + $1.grossSeconds } == 2_700)
        #expect(snapshot.daily.reduce(0) { $0 + $1.wallSeconds } == 1_800)
        #expect(snapshot.taskBreakdown.first { $0.taskID == firstTask.id }?.grossSeconds == 1_800)
        #expect(snapshot.taskBreakdown.first { $0.taskID == secondTask.id }?.grossSeconds == 900)
        #expect(snapshot.overlaps.count == 1)
        #expect(snapshot.overlaps.first?.start == startOfDay)
        #expect(snapshot.overlaps.first?.end == startOfDay.addingTimeInterval(900))
        #expect(snapshot.overlaps.first?.wallDurationSeconds == 900)
        #expect(snapshot.overlaps.first?.excessDurationSeconds == 900)
        #expect(engineOverview.grossSeconds == snapshot.overview.grossSeconds)
        #expect(engineOverview.wallSeconds == snapshot.overview.wallSeconds)
        #expect(engineOverview.overlapSeconds == snapshot.overview.overlapSeconds)
    }

    @Test @MainActor
    func everyAnalyticsProjectionClipsClockSkewedRowsToNow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 14,
            hour: 12
        )))
        let task = TaskNode(title: "Future-safe", parentID: nil, deviceID: "test")
        let session = TimeSession(
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-3_600),
            titleSnapshot: task.title
        )
        let spanningNow = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(3_600)
        )
        let futureOnly = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(60),
            endedAt: now.addingTimeInterval(3_600)
        )
        let segments = [spanningNow, futureOnly]
        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [task],
            segments: segments,
            sessions: [session],
            taskPathByID: [task.id: task.title],
            taskParentPathByID: [:],
            now: now,
            calendar: calendar
        )
        let engine = AnalyticsEngine().overview(
            segments: segments,
            range: .today,
            now: now,
            calendar: calendar
        )
        let forecastPace = ForecastingService().recentDailyAvailableSeconds(
            segments: segments,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.overview.grossSeconds == 3_600)
        #expect(snapshot.overview.wallSeconds == 3_600)
        #expect(snapshot.daily.reduce(0) { $0 + $1.grossSeconds } == 3_600)
        #expect(snapshot.taskBreakdown.first?.grossSeconds == 3_600)
        #expect(snapshot.rhythm.averageSegmentSeconds == 3_600)
        #expect(snapshot.quality.averageSegmentSeconds == 3_600)
        #expect(snapshot.todayActivity.reduce(0) { total, hour in
            total + hour.slices.reduce(0) { $0 + $1.seconds }
        } == 3_600)
        #expect(snapshot.timeline.entries.count == 1)
        #expect(snapshot.timeline.entries.first?.endedAt == now)
        #expect(snapshot.timeline.displayInterval?.end == now)
        #expect(engine.grossSeconds == 3_600)
        #expect(engine.wallSeconds == 3_600)
        #expect(forecastPace == 3_600)

        let records = AnalyticsStore().recentRecords(
            segments: segments,
            sessions: [session],
            tasks: [task],
            taskIDs: [task.id],
            taskPathByID: [task.id: task.title],
            now: now
        )
        #expect(records.first { $0.id == spanningNow.id }?.durationSeconds == 3_600)
        #expect(records.first { $0.id == futureOnly.id }?.durationSeconds == 0)
    }

    @Test @MainActor
    func dailyCacheAdvancesForAClosedSegmentWhoseEndIsStillInTheFuture() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 14,
            hour: 10
        )))
        let segment = TimeSegment(
            sessionID: UUID(),
            taskID: UUID(),
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800)
        )
        let day = try #require(calendar.dateInterval(of: .day, for: start))
        var cache = LedgerBucketCache()

        let first = cache.summaries(
            segments: [segment],
            interval: day,
            now: start.addingTimeInterval(600),
            calendar: calendar
        )
        let second = cache.summaries(
            segments: [segment],
            interval: day,
            now: start.addingTimeInterval(1_200),
            calendar: calendar
        )

        #expect(first.first?.grossSeconds == 600)
        #expect(second.first?.grossSeconds == 1_200)
        #expect(cache.bucketCount == 1)
    }

    @Test @MainActor
    func analyticsSnapshotResolvesDuplicateCloudRowsBeforeEveryAggregation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12))
        )
        let task = TaskNode(title: "Canonical", parentID: nil, deviceID: "device-a")
        let session = TimeSession(
            taskID: task.id,
            source: .timer,
            deviceID: "device-a",
            startedAt: now.addingTimeInterval(-3_600),
            titleSnapshot: task.title
        )
        let stale = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "device-a",
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-3_000)
        )
        stale.updatedAt = now.addingTimeInterval(-120)

        let winner = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "device-b",
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-2_700)
        )
        winner.id = stale.id
        winner.updatedAt = now.addingTimeInterval(-60)

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [task],
            segments: [stale, winner],
            sessions: [session],
            taskPathByID: [task.id: task.title],
            taskParentPathByID: [:],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.overview.grossSeconds == 900)
        #expect(snapshot.daily.reduce(0) { $0 + $1.grossSeconds } == 900)
        #expect(snapshot.taskBreakdown.first?.grossSeconds == 900)
        #expect(snapshot.rhythm.segmentCount == 1)
        #expect(snapshot.timeline.entries.count == 1)
    }

    @Test @MainActor
    func analyticsStoreOwnsSnapshotCache() {
        let task = TaskNode(title: "Cached Task", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: Date(timeIntervalSince1970: 20_000), titleSnapshot: task.title)
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: session.startedAt,
            endedAt: session.startedAt.addingTimeInterval(600)
        )
        var store = AnalyticsStore()

        #expect(store.cachedSnapshot(for: .today) == nil)

        store.refreshSnapshot(
            range: .today,
            tasks: [task],
            segments: [segment],
            sessions: [session],
            taskPathByID: [task.id: task.title],
            taskParentPathByID: [:],
            now: session.startedAt.addingTimeInterval(900)
        )

        #expect(store.cachedSnapshot(for: .today)?.overview.grossSeconds == 600)
        #expect(store.cachedSnapshot(for: .today)?.taskBreakdown.first?.title == "Cached Task")
    }

    @Test @MainActor
    func explicitHistoricalPeriodsPreserveTheirFinalSecondAndOpenSegmentBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let liveNow = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12))
        )
        let reference = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 12))
        )
        let task = TaskNode(title: "Historical", parentID: nil, deviceID: "test")

        for range in AnalyticsRange.allCases {
            let evaluation = range.evaluation(
                referenceDate: reference,
                liveNow: liveNow,
                calendar: calendar
            )
            let finalSecondSession = TimeSession(
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: evaluation.interval.end.addingTimeInterval(-1),
                titleSnapshot: task.title
            )
            let finalSecond = TimeSegment(
                sessionID: finalSecondSession.id,
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: finalSecondSession.startedAt,
                endedAt: evaluation.interval.end
            )
            let zeroLength = TimeSegment(
                sessionID: finalSecondSession.id,
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: evaluation.interval.end,
                endedAt: evaluation.interval.end
            )

            let snapshot = AnalyticsStore().snapshot(
                range: range,
                period: evaluation.interval,
                tasks: [task],
                segments: [finalSecond, zeroLength],
                sessions: [finalSecondSession],
                taskPathByID: [task.id: task.title],
                taskParentPathByID: [:],
                evaluatedAt: evaluation.cutoff,
                calendar: calendar
            )

            #expect(snapshot.overview.grossSeconds == 1)
            #expect(snapshot.daily.reduce(0) { $0 + $1.grossSeconds } == 1)
        }

        let day = try #require(AnalyticsRange.today.interval(containing: reference, calendar: calendar))
        let openSession = TimeSession(
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: day.end.addingTimeInterval(-3_600),
            titleSnapshot: task.title
        )
        let openSegment = TimeSegment(
            sessionID: openSession.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: openSession.startedAt
        )
        let openSnapshot = AnalyticsStore().snapshot(
            range: .today,
            period: day,
            tasks: [task],
            segments: [openSegment],
            sessions: [openSession],
            taskPathByID: [task.id: task.title],
            taskParentPathByID: [:],
            evaluatedAt: day.end,
            calendar: calendar
        )

        #expect(openSnapshot.overview.grossSeconds == 3_600)
    }

    @Test @MainActor
    func explicitSnapshotCacheUsesTheSelectedPeriodStartInsteadOfItsCutoff() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let reference = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12))
        )
        let liveNow = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12))
        )
        let evaluation = AnalyticsRange.today.evaluation(
            referenceDate: reference,
            liveNow: liveNow,
            calendar: calendar
        )
        var store = AnalyticsStore()

        store.refreshSnapshot(
            range: .today,
            period: evaluation.interval,
            tasks: [],
            segments: [],
            sessions: [],
            taskPathByID: [:],
            taskParentPathByID: [:],
            evaluatedAt: evaluation.cutoff,
            evaluationKey: AnalyticsEvaluationCacheKey(
                evaluation: evaluation,
                liveRefreshBucket: nil,
                calendar: calendar
            ),
            calendar: calendar
        )

        #expect(store.cachedSnapshot(
            for: .today,
            evaluationKey: AnalyticsEvaluationCacheKey(
                evaluation: evaluation,
                liveRefreshBucket: nil,
                calendar: calendar
            )
        ) != nil)
        let nextEvaluation = AnalyticsRange.today.evaluation(
            referenceDate: liveNow,
            liveNow: liveNow,
            calendar: calendar
        )
        #expect(store.cachedSnapshot(
            for: .today,
            evaluationKey: AnalyticsEvaluationCacheKey(
                evaluation: nextEvaluation,
                liveRefreshBucket: nil,
                calendar: calendar
            )
        ) == nil)
    }

    @Test @MainActor
    func taskSnapshotCacheReplacesLiveBucketsAndStaysGloballyBounded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstRefresh = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12))
        )
        let secondRefresh = firstRefresh.addingTimeInterval(60)
        let task = TaskNode(title: "Live task", parentID: nil, deviceID: "test")
        var store = AnalyticsStore()
        let snapshot = store.taskSnapshot(
            range: .today,
            task: task,
            taskIDs: [task.id],
            tasks: [task],
            segments: [],
            sessions: [],
            taskPathByID: [task.id: task.title],
            now: firstRefresh,
            calendar: calendar
        )

        store.cacheTaskSnapshot(snapshot, now: firstRefresh, liveRefreshBucket: 1, calendar: calendar)
        store.cacheTaskSnapshot(snapshot, now: secondRefresh, liveRefreshBucket: 2, calendar: calendar)

        #expect(store.taskSnapshotCacheCount == 1)
        #expect(store.cachedTaskSnapshot(
            taskID: task.id,
            range: .today,
            now: secondRefresh,
            liveRefreshBucket: 1,
            calendar: calendar
        ) == nil)
        #expect(store.cachedTaskSnapshot(
            taskID: task.id,
            range: .today,
            now: secondRefresh,
            liveRefreshBucket: 2,
            calendar: calendar
        ) != nil)

        for index in 0..<40 {
            let anotherTask = TaskNode(title: "Task \(index)", parentID: nil, deviceID: "test")
            let anotherSnapshot = store.taskSnapshot(
                range: .today,
                task: anotherTask,
                taskIDs: [anotherTask.id],
                tasks: [anotherTask],
                segments: [],
                sessions: [],
                taskPathByID: [anotherTask.id: anotherTask.title],
                now: secondRefresh,
                calendar: calendar
            )
            store.cacheTaskSnapshot(
                anotherSnapshot,
                now: secondRefresh,
                liveRefreshBucket: nil,
                calendar: calendar
            )
        }

        #expect(store.taskSnapshotCacheCount == 24)
    }

    @Test @MainActor
    func idleWeekTaskCacheExpiresAtTheNextLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 23, minute: 59))
        )
        let nextDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 0, minute: 1))
        )
        let task = TaskNode(title: "Week task", parentID: nil, deviceID: "test")
        var store = AnalyticsStore()
        let snapshot = store.taskSnapshot(
            range: .week,
            task: task,
            taskIDs: [task.id],
            tasks: [task],
            segments: [],
            sessions: [],
            taskPathByID: [task.id: task.title],
            now: firstDay,
            calendar: calendar
        )
        store.cacheTaskSnapshot(
            snapshot,
            now: firstDay,
            liveRefreshBucket: nil,
            calendar: calendar
        )

        #expect(store.cachedTaskSnapshot(
            taskID: task.id,
            range: .week,
            now: firstDay,
            liveRefreshBucket: nil,
            calendar: calendar
        ) != nil)
        #expect(store.cachedTaskSnapshot(
            taskID: task.id,
            range: .week,
            now: nextDay,
            liveRefreshBucket: nil,
            calendar: calendar
        ) == nil)
    }

    @Test @MainActor
    func pomodoroCompletionIsCountedOnlyInTheIntervalWhereItEnds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12))
        )
        let firstDayStart = calendar.startOfDay(for: firstDay)
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let task = TaskNode(title: "Cross-day focus", parentID: nil, deviceID: "test")
        let session = TimeSession(
            taskID: task.id,
            source: .pomodoro,
            deviceID: "test",
            startedAt: firstDayStart.addingTimeInterval(23 * 3_600 + 30 * 60)
        )
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .pomodoro,
            deviceID: "test",
            startedAt: session.startedAt,
            endedAt: firstDayStart.addingTimeInterval(24 * 3_600 + 30 * 60)
        )

        let firstSnapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [task],
            segments: [segment],
            sessions: [session],
            taskPathByID: [task.id: task.title],
            taskParentPathByID: [:],
            now: firstDay,
            calendar: calendar
        )
        let secondSnapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [task],
            segments: [segment],
            sessions: [session],
            taskPathByID: [task.id: task.title],
            taskParentPathByID: [:],
            now: secondDay,
            calendar: calendar
        )
        let firstEngineOverview = AnalyticsEngine().overview(
            segments: [segment],
            range: .today,
            now: firstDay,
            calendar: calendar
        )
        let secondEngineOverview = AnalyticsEngine().overview(
            segments: [segment],
            range: .today,
            now: secondDay,
            calendar: calendar
        )

        #expect(firstSnapshot.overview.pomodoroCount == 0)
        #expect(secondSnapshot.overview.pomodoroCount == 1)
        #expect(firstEngineOverview.pomodoroCount == 0)
        #expect(secondEngineOverview.pomodoroCount == 1)
    }

    @Test @MainActor
    func analyticsSnapshotCacheIsScopedToTheSelectedCalendarPeriodAndCanBeInvalidated() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12)))
        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        var store = AnalyticsStore()

        store.refreshSnapshot(
            range: .today,
            tasks: [],
            segments: [],
            sessions: [],
            taskPathByID: [:],
            taskParentPathByID: [:],
            now: firstDay,
            calendar: calendar
        )

        #expect(store.cachedSnapshot(for: .today, now: firstDay, calendar: calendar) != nil)
        #expect(store.cachedSnapshot(for: .today, now: nextDay, calendar: calendar) == nil)

        store.invalidateSnapshots()
        #expect(store.cachedSnapshot(for: .today) == nil)
    }

    @Test @MainActor
    func idleWeekSnapshotCacheExpiresAtTheNextLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 23, minute: 59))
        )
        let nextDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 0, minute: 1))
        )
        #expect(
            AnalyticsRange.week.interval(containing: firstDay, calendar: calendar) ==
                AnalyticsRange.week.interval(containing: nextDay, calendar: calendar)
        )
        var store = AnalyticsStore()
        store.refreshSnapshot(
            range: .week,
            tasks: [],
            segments: [],
            sessions: [],
            taskPathByID: [:],
            taskParentPathByID: [:],
            now: firstDay,
            calendar: calendar
        )

        #expect(store.cachedSnapshot(for: .week, now: firstDay, calendar: calendar) != nil)
        #expect(store.cachedSnapshot(for: .week, now: nextDay, calendar: calendar) == nil)
    }

    @Test @MainActor
    func analyticsSnapshotOwnsTodayTaskActivity() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 12)))
        let startOfDay = calendar.startOfDay(for: now)
        let design = TaskNode(
            title: "Design",
            parentID: nil,
            deviceID: "test",
            colorHex: "5E5CE6",
            iconName: "paintbrush"
        )
        let writing = TaskNode(
            title: "Writing",
            parentID: nil,
            deviceID: "test",
            colorHex: "34C759",
            iconName: "doc.text"
        )
        let designSession = TimeSession(taskID: design.id, source: .timer, deviceID: "test", startedAt: startOfDay)
        let writingSession = TimeSession(taskID: writing.id, source: .timer, deviceID: "test", startedAt: startOfDay)
        let segments = [
            TimeSegment(
                sessionID: designSession.id,
                taskID: design.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(9 * 3_600 + 30 * 60),
                endedAt: startOfDay.addingTimeInterval(10 * 3_600 + 15 * 60)
            ),
            TimeSegment(
                sessionID: writingSession.id,
                taskID: writing.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(10 * 3_600),
                endedAt: startOfDay.addingTimeInterval(11 * 3_600)
            )
        ]

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [design, writing],
            segments: segments,
            sessions: [designSession, writingSession],
            taskPathByID: [design.id: design.title, writing.id: writing.title],
            taskParentPathByID: [:],
            now: now,
            calendar: calendar
        )

        let nine = try #require(snapshot.todayActivity.first { $0.hour == 9 })
        let ten = try #require(snapshot.todayActivity.first { $0.hour == 10 })

        #expect(nine.slices.map(\.taskID) == [design.id])
        #expect(nine.slices.first?.seconds == 30 * 60)
        #expect(nine.slices.first?.colorHex == "5E5CE6")
        #expect(nine.slices.first?.symbolName == "paintbrush")
        #expect(ten.slices.map(\.taskID) == [writing.id, design.id])
        #expect(ten.slices.map(\.seconds) == [3_600, 15 * 60])
    }

    @Test @MainActor
    func analyticsSnapshotOwnsTodayTimelineReadModel() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 12)))
        let day = calendar.startOfDay(for: now)
        let parent = TaskNode(title: "Client", parentID: nil, deviceID: "test", colorHex: "FF9500", iconName: "briefcase")
        let task = TaskNode(title: "Proposal", parentID: parent.id, deviceID: "test", colorHex: "0A84FF", iconName: "doc.text")
        let firstSession = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: day, titleSnapshot: task.title)
        let secondSession = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: day, titleSnapshot: task.title)
        let segments = [
            TimeSegment(
                sessionID: firstSession.id,
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: day.addingTimeInterval(9 * 3_600),
                endedAt: day.addingTimeInterval(10 * 3_600)
            ),
            TimeSegment(
                sessionID: secondSession.id,
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: day.addingTimeInterval(10 * 3_600),
                endedAt: day.addingTimeInterval(11 * 3_600)
            )
        ]

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [parent, task],
            segments: segments,
            sessions: [firstSession, secondSession],
            taskPathByID: [parent.id: parent.title, task.id: "\(parent.title) / \(task.title)"],
            taskParentPathByID: [task.id: parent.title],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.timeline.entries.count == 2)
        #expect(snapshot.timeline.laneCount == 2)
        #expect(snapshot.timeline.entries.map(\.title) == ["Proposal", "Proposal"])
        #expect(snapshot.timeline.entries.first?.path == "Client")
        #expect(snapshot.timeline.entries.first?.iconName == "doc.text")
        #expect(snapshot.timeline.entries.first?.colorHex == "0A84FF")
        #expect(snapshot.timeline.displayInterval?.start == segments[0].startedAt)
        #expect(snapshot.timeline.displayInterval?.end == segments[1].endedAt)
    }

    @Test @MainActor
    func dailySummaryServiceClipsCrossDaySegmentsIntoEachDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let taskID = UUID()
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 10, hour: 23, minute: 30)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 0, minute: 30)))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 12)))
        let session = TimeSession(taskID: taskID, source: .timer, deviceID: "test", startedAt: start)
        let segment = TimeSegment(sessionID: session.id, taskID: taskID, source: .timer, deviceID: "test", startedAt: start, endedAt: end)

        let summaries = DailySummaryService().summaries(
            segments: [segment],
            interval: DateInterval(start: calendar.startOfDay(for: start), end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end),
            now: now,
            calendar: calendar
        )

        #expect(summaries.map(\.grossSeconds) == [1_800, 1_800])
        #expect(summaries.map(\.wallClockSeconds) == [1_800, 1_800])
        #expect(summaries.first?.taskID == nil)
    }

    @Test @MainActor
    func rhythmCountsEveryCalendarDayTouchedByCrossDayWork() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let monday = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 23))
        )
        let wednesday = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 1))
        )
        let taskID = UUID()
        let segment = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: monday,
            endedAt: wednesday
        )
        let rangeStart = calendar.startOfDay(for: monday)
        let rangeEnd = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: wednesday)))

        let rhythm = AnalyticsStore().rhythm(
            segments: [segment],
            interval: DateInterval(start: rangeStart, end: rangeEnd),
            taskIDs: nil,
            now: wednesday,
            calendar: calendar
        )

        #expect(rhythm.activeDayCount == 3)
        #expect(rhythm.dailyAverageGrossSeconds == (26 * 3_600) / 3)
    }

    @Test @MainActor
    func ledgerBucketCacheInvalidatesOnlyAffectedDayBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let taskID = UUID()
        let dayOne = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9)))
        let dayTwo = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 2, hour: 9)))
        let interval = DateInterval(
            start: calendar.startOfDay(for: dayOne),
            end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dayTwo)) ?? dayTwo
        )
        let firstSession = TimeSession(taskID: taskID, source: .timer, deviceID: "test", startedAt: dayOne)
        let secondSession = TimeSession(taskID: taskID, source: .timer, deviceID: "test", startedAt: dayTwo)
        let firstSegment = TimeSegment(
            sessionID: firstSession.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: dayOne,
            endedAt: dayOne.addingTimeInterval(600)
        )
        let secondSegment = TimeSegment(
            sessionID: secondSession.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: dayTwo,
            endedAt: dayTwo.addingTimeInterval(1_200)
        )
        var cache = LedgerBucketCache()

        let firstSummaries = cache.summaries(
            segments: [firstSegment, secondSegment],
            interval: interval,
            now: dayTwo.addingTimeInterval(2_000),
            calendar: calendar
        )
        #expect(firstSummaries.map(\.grossSeconds) == [600, 1_200])
        #expect(cache.bucketCount == 2)

        cache.invalidate(intervals: [
            DateInterval(start: calendar.startOfDay(for: dayTwo), duration: 24 * 60 * 60)
        ])
        #expect(cache.bucketCount == 1)

        let longerSecondSegment = TimeSegment(
            sessionID: secondSession.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: dayTwo,
            endedAt: dayTwo.addingTimeInterval(1_800)
        )
        let refreshedSummaries = cache.summaries(
            segments: [firstSegment, longerSecondSegment],
            interval: interval,
            now: dayTwo.addingTimeInterval(2_000),
            calendar: calendar
        )

        #expect(refreshedSummaries.map(\.grossSeconds) == [600, 1_800])
        #expect(cache.bucketCount == 2)
    }

    @Test @MainActor
    func ledgerBucketCacheUsesCalendarDayForDSTInvalidation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let intervalEnd = try #require(calendar.date(byAdding: .day, value: 1, to: secondDay))
        var cache = LedgerBucketCache()

        _ = cache.summaries(
            segments: [],
            interval: DateInterval(start: firstDay, end: intervalEnd),
            now: intervalEnd,
            calendar: calendar
        )
        #expect(cache.bucketCount == 2)

        cache.invalidate(intervals: [
            DateInterval(start: secondDay.addingTimeInterval(1_800), duration: 60)
        ])

        #expect(cache.bucketCount == 1)
    }

    @Test @MainActor
    func ledgerBucketCacheEvictsLeastRecentlyUsedHistoryBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        )
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let thirdDay = try #require(calendar.date(byAdding: .day, value: 2, to: firstDay))
        let dayInterval: (Date) -> DateInterval = { start in
            DateInterval(
                start: start,
                end: calendar.date(byAdding: .day, value: 1, to: start) ?? start
            )
        }
        var cache = LedgerBucketCache(maximumBucketCount: 2)

        _ = cache.summaries(
            segments: [],
            interval: dayInterval(firstDay),
            now: thirdDay,
            calendar: calendar
        )
        _ = cache.summaries(
            segments: [],
            interval: dayInterval(secondDay),
            now: thirdDay,
            calendar: calendar
        )
        _ = cache.summaries(
            segments: [],
            interval: dayInterval(firstDay),
            now: thirdDay,
            calendar: calendar
        )
        _ = cache.summaries(
            segments: [],
            interval: dayInterval(thirdDay),
            now: thirdDay.addingTimeInterval(86_400),
            calendar: calendar
        )

        #expect(cache.bucketCount == 2)
        cache.invalidate(intervals: [dayInterval(firstDay)])
        #expect(cache.bucketCount == 1)
    }

    @Test @MainActor
    func ledgerBucketCacheSeparatesPartialIntervalsOnTheSameDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let taskID = UUID()
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 7,
            hour: 10
        )))
        let session = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start
        )
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(7_200)
        )
        var cache = LedgerBucketCache()

        let oneHour = cache.summaries(
            segments: [segment],
            interval: DateInterval(start: start, duration: 3_600),
            now: start.addingTimeInterval(7_200),
            calendar: calendar
        )
        let twoHours = cache.summaries(
            segments: [segment],
            interval: DateInterval(start: start, duration: 7_200),
            now: start.addingTimeInterval(7_200),
            calendar: calendar
        )

        #expect(oneHour.map(\.grossSeconds) == [3_600])
        #expect(twoHours.map(\.grossSeconds) == [7_200])
        #expect(cache.bucketCount == 2)
    }

    @Test @MainActor
    func ledgerBucketCacheSplitsLongSegmentsAcrossDayBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let taskID = UUID()
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 4, hour: 23)))
        let end = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 6, hour: 1)))
        let interval = DateInterval(
            start: calendar.startOfDay(for: start),
            end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        )
        let session = TimeSession(taskID: taskID, source: .timer, deviceID: "test", startedAt: start)
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: end
        )
        var cache = LedgerBucketCache()

        let summaries = cache.summaries(
            segments: [segment],
            interval: interval,
            now: end,
            calendar: calendar
        )

        #expect(summaries.map(\.grossSeconds) == [3_600, 86_400, 3_600])
        #expect(summaries.map(\.wallClockSeconds) == [3_600, 86_400, 3_600])
        #expect(cache.bucketCount == 3)
    }

    @Test @MainActor
    func analyticsStoreBuildsDailyPointsThroughLedgerBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let task = TaskNode(title: "Bucketed Analytics", parentID: nil, deviceID: "test")
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 3, hour: 10)))
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: start, titleSnapshot: task.title)
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(900)
        )
        var store = AnalyticsStore()

        let snapshot = store.refreshSnapshot(
            range: .month,
            tasks: [task],
            segments: [segment],
            sessions: [session],
            taskPathByID: [task.id: task.title],
            taskParentPathByID: [:],
            now: start.addingTimeInterval(900),
            calendar: calendar
        )

        #expect(snapshot.daily.contains { $0.date == calendar.startOfDay(for: start) && $0.grossSeconds == 900 })
        #expect(store.ledgerBucketCount >= 1)
    }

    @Test @MainActor
    func liveComparisonExcludesLaterActivityFromThePreviousDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let cutoff = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 9,
            hour: 12
        )))
        let currentStart = calendar.startOfDay(for: cutoff)
        let previousStart = try #require(calendar.date(byAdding: .day, value: -1, to: currentStart))
        let taskID = UUID()
        let segments = [
            TimeSegment(
                sessionID: UUID(),
                taskID: taskID,
                source: .timer,
                deviceID: "test",
                startedAt: currentStart.addingTimeInterval(9 * 3_600),
                endedAt: currentStart.addingTimeInterval(10 * 3_600)
            ),
            TimeSegment(
                sessionID: UUID(),
                taskID: taskID,
                source: .timer,
                deviceID: "test",
                startedAt: previousStart.addingTimeInterval(9 * 3_600),
                endedAt: previousStart.addingTimeInterval(10 * 3_600)
            ),
            TimeSegment(
                sessionID: UUID(),
                taskID: taskID,
                source: .timer,
                deviceID: "test",
                startedAt: previousStart.addingTimeInterval(15 * 3_600),
                endedAt: previousStart.addingTimeInterval(16 * 3_600)
            )
        ]

        let comparison = AnalyticsStore().comparison(
            segments: segments,
            range: .today,
            now: cutoff,
            calendar: calendar
        )

        #expect(comparison.window.basis == .matchedProgress)
        #expect(comparison.window.current.end == cutoff)
        #expect(comparison.window.previous.end == previousStart.addingTimeInterval(12 * 3_600))
        #expect(comparison.currentGrossSeconds == 3_600)
        #expect(comparison.previousGrossSeconds == 3_600)
        #expect(comparison.grossDeltaSeconds == 0)
    }

    @Test @MainActor
    func liveWeekAndMonthComparisonsUseTheSameCalendarProgress() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let weekCutoff = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 9,
            hour: 14,
            minute: 30
        )))
        let monthCutoff = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 15,
            hour: 14,
            minute: 30
        )))
        let expectedWeekEnd = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 2,
            hour: 14,
            minute: 30
        )))
        let expectedMonthEnd = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 15,
            hour: 14,
            minute: 30
        )))
        let store = AnalyticsStore()
        let weekInterval = try #require(AnalyticsRange.week.interval(
            containing: weekCutoff,
            calendar: calendar
        ))
        let monthInterval = try #require(AnalyticsRange.month.interval(
            containing: monthCutoff,
            calendar: calendar
        ))

        let weekWindow = try #require(store.comparisonWindow(
            for: .week,
            currentInterval: weekInterval,
            evaluatedAt: weekCutoff,
            calendar: calendar
        ))
        let monthWindow = try #require(store.comparisonWindow(
            for: .month,
            currentInterval: monthInterval,
            evaluatedAt: monthCutoff,
            calendar: calendar
        ))

        #expect(weekWindow.basis == .matchedProgress)
        #expect(weekWindow.previous.end == expectedWeekEnd)
        #expect(monthWindow.basis == .matchedProgress)
        #expect(monthWindow.previous.end == expectedMonthEnd)
    }

    @Test @MainActor
    func matchedComparisonPreservesLocalNoonAcrossDSTAndClampsShortMonths() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let springNoon = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 12
        )))
        let marchThirtyFirstNoon = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 31,
            hour: 12
        )))
        let expectedShortMonthEnd = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 1
        )))
        let store = AnalyticsStore()
        let dstInterval = try #require(AnalyticsRange.today.interval(
            containing: springNoon,
            calendar: calendar
        ))
        let shortMonthInterval = try #require(AnalyticsRange.month.interval(
            containing: marchThirtyFirstNoon,
            calendar: calendar
        ))

        let dstWindow = try #require(store.comparisonWindow(
            for: .today,
            currentInterval: dstInterval,
            evaluatedAt: springNoon,
            calendar: calendar
        ))
        let shortMonthWindow = try #require(store.comparisonWindow(
            for: .month,
            currentInterval: shortMonthInterval,
            evaluatedAt: marchThirtyFirstNoon,
            calendar: calendar
        ))

        #expect(calendar.component(.hour, from: dstWindow.current.end) == 12)
        #expect(calendar.component(.hour, from: dstWindow.previous.end) == 12)
        #expect(dstWindow.current.duration == 11 * 3_600)
        #expect(dstWindow.previous.duration == 12 * 3_600)
        #expect(shortMonthWindow.basis == .matchedProgress)
        #expect(shortMonthWindow.previous.end == expectedShortMonthEnd)
    }

    @Test @MainActor
    func completedAndFuturePeriodsExposeTheirComparisonBasis() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let historicalReference = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 15
        )))
        let futureReference = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 15
        )))
        let historical = try #require(AnalyticsRange.month.interval(
            containing: historicalReference,
            calendar: calendar
        ))
        let future = try #require(AnalyticsRange.month.interval(
            containing: futureReference,
            calendar: calendar
        ))
        let store = AnalyticsStore()

        let completedWindow = try #require(store.comparisonWindow(
            for: .month,
            currentInterval: historical,
            evaluatedAt: historical.end,
            calendar: calendar
        ))
        let futureWindow = try #require(store.comparisonWindow(
            for: .month,
            currentInterval: future,
            evaluatedAt: future.start,
            calendar: calendar
        ))

        #expect(completedWindow.basis == .completePeriods)
        #expect(completedWindow.current == historical)
        #expect(completedWindow.previous.end == historical.start)
        #expect(futureWindow.basis == .matchedProgress)
        #expect(futureWindow.current.duration == 0)
        #expect(futureWindow.previous.duration == 0)
    }
}
