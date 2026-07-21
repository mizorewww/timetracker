import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct TodayActivityHeatmapRefreshTests {
    @Test @MainActor
    func refreshIdentityAdvancesByMinuteOnlyWhileATimerIsRunning() throws {
        let calendar = testCalendar()
        let now = try testDate(calendar: calendar)
        let later = now.addingTimeInterval(60)
        let taskID = UUID()
        let store = TimeTrackerStore()
        store.preferences.todayHeatmapTaskIDs = [taskID]

        let idleNow = HomeActivityHeatmapRefreshRequest(
            store: store,
            now: now,
            calendar: calendar,
            clockRevision: 0
        )
        let idleLater = HomeActivityHeatmapRefreshRequest(
            store: store,
            now: later,
            calendar: calendar,
            clockRevision: 0
        )

        #expect(idleNow == idleLater)
        #expect(idleNow.liveRefreshBucket == nil)

        store.activeSegments = [
            TimeSegment(
                sessionID: UUID(),
                taskID: taskID,
                source: .timer,
                deviceID: "test",
                startedAt: now.addingTimeInterval(-3_600)
            )
        ]
        let runningNow = HomeActivityHeatmapRefreshRequest(
            store: store,
            now: now,
            calendar: calendar,
            clockRevision: 0
        )
        let runningLater = HomeActivityHeatmapRefreshRequest(
            store: store,
            now: later,
            calendar: calendar,
            clockRevision: 0
        )

        #expect(runningNow != runningLater)
        #expect(runningNow.liveRefreshBucket != nil)
        let nowBucket = try #require(runningNow.liveRefreshBucket)
        let laterBucket = try #require(runningLater.liveRefreshBucket)
        #expect(laterBucket == nowBucket + 1)
    }

    @Test @MainActor
    func runningTimerSnapshotGrowsWhenTheTimelineRefreshes() throws {
        let calendar = testCalendar()
        let now = try testDate(calendar: calendar)
        let task = TaskNode(
            title: "Running",
            parentID: nil,
            deviceID: "test",
            colorHex: "1677FF"
        )
        let segment = TimeSegment(
            sessionID: UUID(),
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-3_600)
        )
        let store = TimeTrackerStore()
        store.tasks = [task]
        store.activeSegments = [segment]
        store.allSegments = [segment]
        store.preferences.todayHeatmapTaskIDs = [task.id]

        let initial = try #require(
            store.todayTaskActivityHeatmapSnapshots(
                now: now,
                calendar: calendar
            ).first
        )
        let refreshed = try #require(
            store.todayTaskActivityHeatmapSnapshots(
                now: now.addingTimeInterval(60),
                calendar: calendar
            ).first
        )

        #expect(initial.metric == .trackedDuration)
        #expect(initial.totalValue == 3_600)
        #expect(refreshed.totalValue == 3_660)
    }

    private func testCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func testDate(calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 9,
            hour: 12,
            minute: 10
        )))
    }
}
