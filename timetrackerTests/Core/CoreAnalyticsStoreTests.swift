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
        #expect(snapshot.overlaps.count == 1)
        #expect(snapshot.overlaps.first?.durationSeconds == 3_600)
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
        #expect(snapshot.rangeSegments.count == 1)
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
            calendar: calendar
        )

        #expect(store.cachedSnapshot(for: .today, period: evaluation.interval) != nil)
        let nextPeriod = try #require(
            AnalyticsRange.today.interval(containing: liveNow, calendar: calendar)
        )
        #expect(store.cachedSnapshot(for: .today, period: nextPeriod) == nil)
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
}
