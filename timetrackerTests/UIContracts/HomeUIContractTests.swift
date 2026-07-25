import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct HomeUIContractTests {
    @Test @MainActor
    func todayMetricsClipBothDaysAndSeparateGrossFromWallTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 9,
            hour: 12
        )))
        let todayStart = calendar.startOfDay(for: now)
        let previousStart = try #require(calendar.date(byAdding: .day, value: -1, to: todayStart))
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Metrics",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        func addSegment(start: Date, end: Date) throws {
            _ = try timeRepository.addManualSegment(
                taskID: task.id,
                startedAt: start,
                endedAt: end,
                note: nil
            )
        }

        try addSegment(
            start: previousStart.addingTimeInterval(23.5 * 3600),
            end: todayStart.addingTimeInterval(30 * 60)
        )
        try addSegment(
            start: previousStart.addingTimeInterval(23.75 * 3600),
            end: todayStart.addingTimeInterval(15 * 60)
        )
        try addSegment(
            start: todayStart.addingTimeInterval(9 * 3600),
            end: todayStart.addingTimeInterval(10 * 3600)
        )
        try addSegment(
            start: todayStart.addingTimeInterval(9.5 * 3600),
            end: todayStart.addingTimeInterval(10.5 * 3600)
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let snapshot = store.todayMetricsSnapshot(now: now, calendar: calendar)

        #expect(snapshot.grossSeconds == 9900)
        #expect(snapshot.wallSeconds == 7200)
        #expect(snapshot.previousGrossSeconds == 2700)
        #expect(snapshot.previousWallSeconds == 1800)
    }

    @Test @MainActor
    func weeklyGrossTimeUsesCalendarDaysAndGrossOverlapSemantics() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 9,
            hour: 12
        )))
        let week = try #require(
            calendar.dateInterval(of: .weekOfYear, for: now)
        )
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        )
        let task = try taskRepository.createTask(
            title: "Weekly",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        func addSegment(start: Date, end: Date) throws {
            _ = try timeRepository.addManualSegment(
                taskID: task.id,
                startedAt: start,
                endedAt: end,
                note: nil
            )
        }

        try addSegment(
            start: week.start.addingTimeInterval(-1800),
            end: week.start.addingTimeInterval(1800)
        )
        try addSegment(
            start: week.start.addingTimeInterval(9 * 3600),
            end: week.start.addingTimeInterval(10 * 3600)
        )
        try addSegment(
            start: week.start.addingTimeInterval(9.5 * 3600),
            end: week.start.addingTimeInterval(10.5 * 3600)
        )
        let wednesday = try #require(
            calendar.date(byAdding: .day, value: 2, to: week.start)
        )
        try addSegment(
            start: wednesday.addingTimeInterval(23.5 * 3600),
            end: wednesday.addingTimeInterval(24.5 * 3600)
        )
        try addSegment(
            start: now.addingTimeInterval(-2 * 3600),
            end: now.addingTimeInterval(3600)
        )
        let friday = try #require(
            calendar.date(byAdding: .day, value: 4, to: week.start)
        )
        try addSegment(
            start: friday.addingTimeInterval(10 * 3600),
            end: friday.addingTimeInterval(11 * 3600)
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let snapshot = store.weeklyGrossTimeSnapshot(
            now: now,
            calendar: calendar
        )

        #expect(snapshot.interval == week)
        #expect(snapshot.daily.count == 4)
        #expect(snapshot.daily.map(\.grossSeconds) == [9000, 0, 1800, 9000])
        #expect(snapshot.daily.map(\.wallSeconds) == [7200, 0, 1800, 9000])
        #expect(snapshot.totalGrossSeconds == 19800)
        #expect(snapshot.hasTrackedTime)
        #expect(snapshot.requiresLiveRefresh)
    }

    @Test @MainActor
    func weeklyGrossTimeAdvancesAnOpenTimerAndKeepsMinuteRefreshAlive() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 8,
            hour: 10
        )))
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test",
            nowProvider: { start }
        )
        let task = try taskRepository.createTask(
            title: "Open timer",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let segment = try timeRepository.startTask(
            taskID: task.id,
            source: .timer
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let firstDate = start.addingTimeInterval(600)
        let secondDate = start.addingTimeInterval(1200)

        let first = store.weeklyGrossTimeSnapshot(
            now: firstDate,
            calendar: calendar
        )
        let second = store.weeklyGrossTimeSnapshot(
            now: secondDate,
            calendar: calendar
        )
        let firstRequest = HomeWeeklyGrossTimeRefreshRequest(
            store: store,
            snapshot: first,
            now: firstDate,
            clockRevision: 0,
            calendar: calendar
        )
        let secondRequest = HomeWeeklyGrossTimeRefreshRequest(
            store: store,
            snapshot: second,
            now: secondDate,
            clockRevision: 0,
            calendar: calendar
        )

        #expect(segment.endedAt == nil)
        #expect(first.totalGrossSeconds == 600)
        #expect(second.totalGrossSeconds == 1200)
        #expect(first.requiresLiveRefresh)
        #expect(second.requiresLiveRefresh)
        #expect(firstRequest.evaluationKey.liveRefreshBucket != nil)
        #expect(secondRequest.evaluationKey.liveRefreshBucket != nil)
        #expect(
            firstRequest.evaluationKey.liveRefreshBucket !=
                secondRequest.evaluationKey.liveRefreshBucket
        )
    }

    @Test @MainActor
    func weeklyGrossTimeEmptySnapshotDoesNotRequireLiveRefresh() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 9,
            hour: 12
        )))
        let week = try #require(
            calendar.dateInterval(of: .weekOfYear, for: now)
        )
        let expectedDates = try (0 ..< 4).map { offset in
            try #require(
                calendar.date(byAdding: .day, value: offset, to: week.start)
            )
        }
        let context = try makeTestContext()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let snapshot = store.weeklyGrossTimeSnapshot(
            now: now,
            calendar: calendar
        )
        let request = HomeWeeklyGrossTimeRefreshRequest(
            store: store,
            snapshot: snapshot,
            now: now,
            clockRevision: 0,
            calendar: calendar
        )

        #expect(snapshot.interval == week)
        #expect(snapshot.daily.map(\.date) == expectedDates)
        #expect(snapshot.daily.allSatisfy { $0.grossSeconds == 0 })
        #expect(snapshot.daily.allSatisfy { $0.wallSeconds == 0 })
        #expect(snapshot.totalGrossSeconds == 0)
        #expect(snapshot.hasTrackedTime == false)
        #expect(snapshot.requiresLiveRefresh == false)
        #expect(request.evaluationKey.liveRefreshBucket == nil)
    }

    @Test @MainActor
    func weeklyGrossTimeHonorsSundayFirstCalendarAcrossDSTDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = try #require(
            TimeZone(identifier: "America/Los_Angeles")
        )
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 10,
            hour: 12
        )))
        let week = try #require(
            calendar.dateInterval(of: .weekOfYear, for: now)
        )
        let sunday = week.start
        let monday = try #require(
            calendar.date(byAdding: .day, value: 1, to: sunday)
        )
        let tuesday = try #require(
            calendar.date(byAdding: .day, value: 2, to: sunday)
        )
        let sundayDay = try #require(
            calendar.dateInterval(of: .day, for: sunday)
        )
        let segmentStart = try #require(
            calendar.date(byAdding: .minute, value: 30, to: sunday)
        )
        let segmentEnd = try #require(
            calendar.date(byAdding: .minute, value: 30, to: monday)
        )
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        )
        let task = try taskRepository.createTask(
            title: "DST week",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: segmentStart,
            endedAt: segmentEnd,
            note: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let snapshot = store.weeklyGrossTimeSnapshot(
            now: now,
            calendar: calendar
        )

        #expect(
            calendar.dateComponents(
                [.year, .month, .day, .weekday, .hour],
                from: week.start
            ) == DateComponents(
                year: 2026,
                month: 3,
                day: 8,
                hour: 0,
                weekday: 1
            )
        )
        #expect(week.duration == 167 * 3600)
        #expect(sundayDay.duration == 23 * 3600)
        #expect(snapshot.interval == week)
        #expect(snapshot.daily.map(\.date) == [sunday, monday, tuesday])
        #expect(snapshot.daily.map(\.grossSeconds) == [81000, 1800, 0])
        #expect(snapshot.daily.map(\.wallSeconds) == [81000, 1800, 0])
        #expect(snapshot.totalGrossSeconds == 82800)
        #expect(snapshot.hasTrackedTime)
        #expect(snapshot.requiresLiveRefresh == false)
    }

    @Test @MainActor
    func weeklyGrossTimeReevaluatesAClosedFutureEndAtEachCutoff() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 8,
            hour: 10
        )))
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        )
        let task = try taskRepository.createTask(
            title: "Clock skew",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(3600),
            note: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let first = store.weeklyGrossTimeSnapshot(
            now: start.addingTimeInterval(600),
            calendar: calendar
        )
        let second = store.weeklyGrossTimeSnapshot(
            now: start.addingTimeInterval(1200),
            calendar: calendar
        )

        #expect(first.totalGrossSeconds == 600)
        #expect(second.totalGrossSeconds == 1200)
        #expect(first.requiresLiveRefresh)
        #expect(second.requiresLiveRefresh)
    }

    @Test @MainActor
    func weeklyGrossTimeRefreshesAcrossFutureStartAndClockRewindBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 8,
            hour: 10
        )))
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        )
        let task = try taskRepository.createTask(
            title: "Future import",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(3600),
            note: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let beforeDate = start.addingTimeInterval(-600)
        let duringDate = start.addingTimeInterval(600)
        let afterDate = start.addingTimeInterval(4200)

        let before = store.weeklyGrossTimeSnapshot(
            now: beforeDate,
            calendar: calendar
        )
        let during = store.weeklyGrossTimeSnapshot(
            now: duringDate,
            calendar: calendar
        )
        let after = store.weeklyGrossTimeSnapshot(
            now: afterDate,
            calendar: calendar
        )
        let rewound = store.weeklyGrossTimeSnapshot(
            now: beforeDate,
            calendar: calendar
        )
        let waitingRequest = HomeWeeklyGrossTimeRefreshRequest(
            store: store,
            snapshot: before,
            now: beforeDate,
            clockRevision: 0,
            calendar: calendar
        )
        let settledRequest = HomeWeeklyGrossTimeRefreshRequest(
            store: store,
            snapshot: after,
            now: afterDate,
            clockRevision: 0,
            calendar: calendar
        )
        let rewoundRequest = HomeWeeklyGrossTimeRefreshRequest(
            store: store,
            snapshot: after,
            now: beforeDate,
            clockRevision: 1,
            calendar: calendar
        )

        #expect(before.totalGrossSeconds == 0)
        #expect(before.requiresLiveRefresh)
        #expect(waitingRequest.evaluationKey.liveRefreshBucket != nil)
        #expect(during.totalGrossSeconds == 600)
        #expect(during.requiresLiveRefresh)
        #expect(after.totalGrossSeconds == 3600)
        #expect(after.requiresLiveRefresh == false)
        #expect(rewound.totalGrossSeconds == 0)
        #expect(rewound.requiresLiveRefresh)
        #expect(settledRequest.evaluationKey.liveRefreshBucket == nil)
        #expect(rewoundRequest != settledRequest)
    }

    @Test @MainActor
    func todayCountdownOrderingIsStableForMatchingDatesAndTitles() {
        let date = Date(timeIntervalSince1970: 10000)
        let later = CountdownEvent(title: "Later", date: date.addingTimeInterval(1), deviceID: "test")
        let beta = CountdownEvent(title: "Beta", date: date, deviceID: "test")
        let alphaB = CountdownEvent(title: "Alpha", date: date, deviceID: "test")
        let alphaA = CountdownEvent(title: "Alpha", date: date, deviceID: "test")
        alphaA.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        alphaB.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let sorted = TodayHomeContent.sortedCountdownEvents([later, beta, alphaB, alphaA])

        #expect(sorted.map(\.id) == [alphaA.id, alphaB.id, beta.id, later.id])
    }

    @Test @MainActor
    func quickStartRecentTasksRankByFrequencyAndSkipPinnedTasks() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pinnedTask = try taskRepository.createTask(title: "Pinned", parentID: nil, colorHex: nil, iconName: nil)
        let frequentTask = try taskRepository.createTask(title: "Frequent", parentID: nil, colorHex: nil, iconName: nil)
        let occasionalTask = try taskRepository.createTask(title: "Occasional", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 10000)

        _ = try timeRepository.addManualSegment(
            taskID: occasionalTask.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: frequentTask.id,
            startedAt: start.addingTimeInterval(1000),
            endedAt: start.addingTimeInterval(1600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: frequentTask.id,
            startedAt: start.addingTimeInterval(2000),
            endedAt: start.addingTimeInterval(2600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: pinnedTask.id,
            startedAt: start.addingTimeInterval(3000),
            endedAt: start.addingTimeInterval(3600),
            note: nil
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let quickStartTasks = store.frequentRecentTasks(excluding: [pinnedTask.id], limit: 2)

        #expect(quickStartTasks.map(\.id) == [frequentTask.id, occasionalTask.id])
    }
}
