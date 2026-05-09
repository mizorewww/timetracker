import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreAnalyticsStoreTests {
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
        #expect(snapshot.overlaps.count == 1)
        #expect(snapshot.overlaps.first?.durationSeconds == 3_600)
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
            now: start,
            calendar: calendar
        )

        #expect(snapshot.daily.contains { $0.date == calendar.startOfDay(for: start) && $0.grossSeconds == 900 })
        #expect(store.ledgerBucketCount >= 1)
    }
}
