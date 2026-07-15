import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct AnalyticsTimelineTests {
    @Test @MainActor
    func analyticsOverviewBreakdownAndOverlapUseSegments() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "Coding", parentID: nil, colorHex: "1677FF", iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Meeting", parentID: nil, colorHex: "EF4444", iconName: nil)
        secondTask.status = .planned
        let calendar = Calendar.current
        let now = fixedAnalyticsMidday()
        let startOfDay = calendar.startOfDay(for: now)

        _ = try timeRepository.addManualSegment(
            taskID: firstTask.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3600),
            endedAt: startOfDay.addingTimeInterval(10 * 3600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: secondTask.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3600 + 30 * 60),
            endedAt: startOfDay.addingTimeInterval(10 * 3600 + 30 * 60),
            note: nil
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        let overview = store.analyticsOverview(for: .week, now: now)
        #expect(overview.grossSeconds == 7_200)
        #expect(overview.wallSeconds == 5_400)
        #expect(overview.overlapSeconds == 1_800)

        let tasks = store.taskBreakdown(range: .week, now: now)
        #expect(tasks.count == 2)
        #expect(tasks.first?.grossSeconds == 3_600)
        #expect(tasks.first { $0.taskID == secondTask.id }?.status == .planned)

        let overlaps = store.overlapSegments(range: .week, now: now)
        #expect(overlaps.first?.durationSeconds == 1_800)
    }


    @Test @MainActor
    func todayHourlyBreakdownClipsSegmentsIntoHourBuckets() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Design", parentID: nil, colorHex: nil, iconName: nil)
        let calendar = Calendar.current
        let now = fixedAnalyticsMidday()
        let startOfDay = calendar.startOfDay(for: now)

        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3_600 + 30 * 60),
            endedAt: startOfDay.addingTimeInterval(10 * 3_600 + 15 * 60),
            note: nil
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let hourly = store.hourlyBreakdown(for: now, now: now)

        #expect(hourly.count == 24)
        #expect(hourly[9].grossSeconds == 30 * 60)
        #expect(hourly[10].grossSeconds == 15 * 60)
        #expect(hourly[9].wallSeconds == 30 * 60)
    }

    @Test @MainActor
    func todayHourlyBreakdownSeparatesGrossAndWallForOverlap() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "Coding", parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Meeting", parentID: nil, colorHex: nil, iconName: nil)
        let calendar = Calendar.current
        let now = fixedAnalyticsMidday()
        let startOfDay = calendar.startOfDay(for: now)

        _ = try timeRepository.addManualSegment(
            taskID: firstTask.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3_600),
            endedAt: startOfDay.addingTimeInterval(10 * 3_600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: secondTask.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3_600 + 30 * 60),
            endedAt: startOfDay.addingTimeInterval(10 * 3_600),
            note: nil
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let nine = store.hourlyBreakdown(for: now, now: now)[9]

        #expect(nine.grossSeconds == 90 * 60)
        #expect(nine.wallSeconds == 60 * 60)
    }

    @Test @MainActor
    func taskBreakdownKeepsLedgerVisibleAfterTaskSoftDelete() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Client Research", parentID: nil, colorHex: "1677FF", iconName: nil)
        let now = fixedAnalyticsMidday()

        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-1_800),
            note: "Billable"
        )
        try taskRepository.softDeleteTask(taskID: task.id)

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let breakdown = store.taskBreakdown(range: .today, now: now)

        #expect(breakdown.count == 1)
        #expect(breakdown.first?.title == "Client Research")
        #expect(breakdown.first?.path == AppStrings.localized("task.deleted.path"))
        #expect(breakdown.first?.grossSeconds == 1_800)
    }

    @Test @MainActor
    func analyticsDecisionSnapshotBuildsComparisonRhythmQualityAndGroups() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 12)))
        let startOfDay = calendar.startOfDay(for: now)
        let previousDay = startOfDay.addingTimeInterval(-86_400)
        let category = TaskCategory(title: "Work", deviceID: "test", colorHex: "1677FF", iconName: "briefcase")
        let root = TaskNode(title: "Client", parentID: nil, deviceID: "test", colorHex: "1677FF", iconName: "folder")
        let child = TaskNode(title: "Review", parentID: root.id, deviceID: "test", colorHex: "34C759", iconName: "doc.text")
        let assignment = TaskCategoryAssignment(taskID: root.id, categoryID: category.id, deviceID: "test")
        let rootSession = TimeSession(taskID: root.id, source: .timer, deviceID: "test", startedAt: startOfDay)
        let childSession = TimeSession(taskID: child.id, source: .timer, deviceID: "test", startedAt: startOfDay)
        let previousSession = TimeSession(taskID: root.id, source: .timer, deviceID: "test", startedAt: previousDay)
        let segments = [
            TimeSegment(
                sessionID: rootSession.id,
                taskID: root.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(9 * 3_600),
                endedAt: startOfDay.addingTimeInterval(10 * 3_600)
            ),
            TimeSegment(
                sessionID: childSession.id,
                taskID: child.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(9 * 3_600 + 50 * 60),
                endedAt: startOfDay.addingTimeInterval(10 * 3_600 + 10 * 60)
            ),
            TimeSegment(
                sessionID: childSession.id,
                taskID: child.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(11 * 3_600),
                endedAt: startOfDay.addingTimeInterval(11 * 3_600 + 120)
            ),
            TimeSegment(
                sessionID: previousSession.id,
                taskID: root.id,
                source: .timer,
                deviceID: "test",
                startedAt: previousDay.addingTimeInterval(9 * 3_600),
                endedAt: previousDay.addingTimeInterval(9 * 3_600 + 30 * 60)
            )
        ]

        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [root, child],
            taskCategories: [category],
            taskCategoryAssignments: [assignment],
            segments: segments,
            sessions: [rootSession, childSession, previousSession],
            taskPathByID: [root.id: root.title, child.id: "\(root.title) / \(child.title)"],
            taskParentPathByID: [child.id: root.title],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.comparison.previousGrossSeconds == 1_800)
        #expect(snapshot.comparison.currentGrossSeconds == 4_920)
        #expect(snapshot.rhythm.peakHour == 9)
        #expect(snapshot.quality.shortSegmentCount == 1)
        #expect(snapshot.quality.switchCount >= 1)
        #expect(snapshot.rootBreakdown.first?.title == "Client")
        #expect(snapshot.categoryBreakdown.first?.title == "Work")
        #expect(snapshot.insights.isEmpty == false)
    }

    @Test
    func analyticsTodayRangeCanAnchorToPreviousDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let todayNoon = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 12)))
        let yesterdayNoon = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 12)))
        let todayStart = calendar.startOfDay(for: todayNoon)
        let yesterdayStart = calendar.startOfDay(for: yesterdayNoon)
        let task = TaskNode(title: "Review", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: yesterdayStart)
        let segments = [
            TimeSegment(
                sessionID: session.id,
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: yesterdayStart.addingTimeInterval(9 * 3_600),
                endedAt: yesterdayStart.addingTimeInterval(10 * 3_600)
            ),
            TimeSegment(
                sessionID: session.id,
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: todayStart.addingTimeInterval(9 * 3_600),
                endedAt: todayStart.addingTimeInterval(9 * 3_600 + 30 * 60)
            )
        ]

        let yesterdaySnapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [task],
            segments: segments,
            sessions: [session],
            taskPathByID: [task.id: task.title],
            taskParentPathByID: [:],
            now: yesterdayNoon,
            calendar: calendar
        )
        let todaySnapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: [task],
            segments: segments,
            sessions: [session],
            taskPathByID: [task.id: task.title],
            taskParentPathByID: [:],
            now: todayNoon,
            calendar: calendar
        )

        #expect(yesterdaySnapshot.overview.grossSeconds == 3_600)
        #expect(todaySnapshot.overview.grossSeconds == 1_800)
    }

    @Test @MainActor
    func taskAnalyticsSnapshotIncludesDescendantsAndDirectContribution() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 12)))
        let startOfDay = calendar.startOfDay(for: now)
        let root = TaskNode(title: "Build", parentID: nil, deviceID: "test", colorHex: "1677FF", iconName: "hammer")
        let child = TaskNode(title: "Tests", parentID: root.id, deviceID: "test", colorHex: "FF9500", iconName: "checkmark")
        let rootSession = TimeSession(taskID: root.id, source: .timer, deviceID: "test", startedAt: startOfDay)
        let childSession = TimeSession(taskID: child.id, source: .timer, deviceID: "test", startedAt: startOfDay)
        let segments = [
            TimeSegment(
                sessionID: rootSession.id,
                taskID: root.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(8 * 3_600),
                endedAt: startOfDay.addingTimeInterval(9 * 3_600)
            ),
            TimeSegment(
                sessionID: childSession.id,
                taskID: child.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(10 * 3_600),
                endedAt: startOfDay.addingTimeInterval(10 * 3_600 + 30 * 60)
            )
        ]

        let snapshot = AnalyticsStore().taskSnapshot(
            range: .today,
            task: root,
            taskIDs: [root.id, child.id],
            tasks: [root, child],
            segments: segments,
            sessions: [rootSession, childSession],
            taskPathByID: [root.id: root.title, child.id: "\(root.title) / \(child.title)"],
            now: now,
            calendar: calendar
        )

        #expect(snapshot.overview.grossSeconds == 5_400)
        #expect(snapshot.directSeconds == 3_600)
        #expect(snapshot.descendantSeconds == 1_800)
        #expect(snapshot.childBreakdown.map(\.title).contains("Build"))
        #expect(snapshot.childBreakdown.map(\.title).contains("Tests"))
        #expect(snapshot.recentRecords.count == 2)
    }


    @Test
    func timelineLayoutUsesMinimumNumberOfLanes() {
        let day = Date(timeIntervalSince1970: 0)
        let dayInterval = DateInterval(start: day, duration: 24 * 60 * 60)
        let first = TimelineLayoutItem(id: UUID(), startedAt: day.addingTimeInterval(12 * 60), endedAt: day.addingTimeInterval(34 * 60))
        let second = TimelineLayoutItem(id: UUID(), startedAt: day.addingTimeInterval(20 * 60), endedAt: day.addingTimeInterval(50 * 60))
        let third = TimelineLayoutItem(id: UUID(), startedAt: day.addingTimeInterval(40 * 60), endedAt: day.addingTimeInterval(55 * 60))

        let result = TimelineLayoutEngine.layout(items: [first, second, third], dayInterval: dayInterval)

        #expect(result.laneCount == 2)
        #expect(result.entries.map(\.lane) == [0, 1, 0])
    }

    @Test
    func timelineLayoutKeepsBackToBackSegmentsVisuallySeparated() {
        let day = Date(timeIntervalSince1970: 0)
        let dayInterval = DateInterval(start: day, duration: 24 * 60 * 60)
        let first = TimelineLayoutItem(id: UUID(), startedAt: day.addingTimeInterval(9 * 3600), endedAt: day.addingTimeInterval(10 * 3600))
        let second = TimelineLayoutItem(id: UUID(), startedAt: day.addingTimeInterval(10 * 3600), endedAt: day.addingTimeInterval(11 * 3600))

        let result = TimelineLayoutEngine.layout(items: [first, second], dayInterval: dayInterval)

        #expect(result.laneCount == 2)
        #expect(result.entries.map(\.lane) == [0, 1])
    }

    @Test
    func timelineLayoutClipsCrossDaySegmentsAndUsesVisibleRange() {
        let day = Date(timeIntervalSince1970: 24 * 60 * 60)
        let dayInterval = DateInterval(start: day, duration: 24 * 60 * 60)
        let crossDay = TimelineLayoutItem(
            id: UUID(),
            startedAt: day.addingTimeInterval(-45 * 60),
            endedAt: day.addingTimeInterval(20 * 60)
        )
        let evening = TimelineLayoutItem(
            id: UUID(),
            startedAt: day.addingTimeInterval(20 * 3600),
            endedAt: day.addingTimeInterval(21 * 3600)
        )

        let result = TimelineLayoutEngine.layout(items: [crossDay, evening], dayInterval: dayInterval)

        #expect(result.entries.first?.item.startedAt == day)
        #expect(result.displayInterval.start == day)
        #expect(result.displayInterval.end == evening.endedAt)
    }

    @Test
    func timelineLayoutUsesFirstAndLastVisibleSegmentBounds() {
        let day = Date(timeIntervalSince1970: 48 * 60 * 60)
        let dayInterval = DateInterval(start: day, duration: 24 * 60 * 60)
        let morning = TimelineLayoutItem(
            id: UUID(),
            startedAt: day.addingTimeInterval(9 * 3600),
            endedAt: day.addingTimeInterval(10 * 3600)
        )
        let afternoon = TimelineLayoutItem(
            id: UUID(),
            startedAt: day.addingTimeInterval(14 * 3600),
            endedAt: day.addingTimeInterval(16 * 3600)
        )

        let result = TimelineLayoutEngine.layout(items: [afternoon, morning], dayInterval: dayInterval)

        #expect(result.displayInterval.start == morning.startedAt)
        #expect(result.displayInterval.end == afternoon.endedAt)
    }

    @Test
    func timelineAxisCompressionFoldsLongIdleGaps() {
        let day = Date(timeIntervalSince1970: 72 * 60 * 60)
        let display = DateInterval(start: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(16 * 3600))
        let morning = DateInterval(start: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(10 * 3600))
        let afternoon = DateInterval(start: day.addingTimeInterval(14 * 3600), end: day.addingTimeInterval(16 * 3600))

        let compression = TimelineAxisCompression(displayInterval: display, busyIntervals: [morning, afternoon])

        #expect(compression.omittedGaps.count == 1)
        #expect(abs((compression.omittedGaps.first?.duration ?? 0) - 14_400) < 0.001)
        #expect(compression.compressedDuration < display.duration)
        #expect(compression.ratio(for: afternoon.start) < afternoon.start.timeIntervalSince(display.start) / display.duration)
    }

    @Test
    func timelineAxisCompressionKeepsShortGapsLinear() {
        let day = Date(timeIntervalSince1970: 96 * 60 * 60)
        let display = DateInterval(start: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(11 * 3600))
        let first = DateInterval(start: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(10 * 3600))
        let second = DateInterval(start: day.addingTimeInterval(10 * 3600 + 20 * 60), end: day.addingTimeInterval(11 * 3600))

        let compression = TimelineAxisCompression(displayInterval: display, busyIntervals: [first, second])

        #expect(compression.omittedGaps.isEmpty)
        #expect(compression.compressedDuration == display.duration)
    }


    @Test
    func analyticsTaskDistributionUsesTaskBucketsAndTaskColors() throws {
        let analyticsSource = try sourceText("timetracker/Features/Analytics/Sections/AnalyticsDistributionViews.swift")
        let categorySource = try sourceText("timetracker/Features/Analytics/AnalyticsCategoryDetailView.swift")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(analyticsSource.contains("id: task.taskID.uuidString"))
        #expect(analyticsSource.contains("colorHex: task.colorHex"))
        #expect(analyticsSource.contains("point.status?.rawValue") == false)
        #expect(categorySource.contains("totalSeconds: snapshot.overview.grossSeconds"))
        #expect(categorySource.contains("totalSeconds: max(snapshot.overview.grossSeconds, 1)") == false)
        #expect(categorySource.contains("max(snapshot.rootBreakdown.reduce") == false)
        #expect(categorySource.contains("max(snapshot.categoryBreakdown.reduce") == false)
        #expect(englishStrings.contains("Task Status Distribution") == false)
        #expect(englishStrings.contains("\"analytics.taskUsage.title\" = \"Task Distribution\";"))
    }

    @Test
    func todayActivityDistributionUsesTaskColorBuckets() throws {
        let entrySource = try [
            "timetracker/Features/Analytics/AnalyticsViews.swift",
            "timetracker/Features/Analytics/AnalyticsCategoryDetailView.swift"
        ]
            .map(sourceText)
            .joined(separator: "\n")
        let viewSource = try [
            "timetracker/Features/Analytics/Sections/AnalyticsActivityViews.swift",
            "timetracker/Features/Analytics/Sections/AnalyticsActivityBarViews.swift",
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineViews.swift",
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineRows.swift",
            "timetracker/Features/Analytics/Timeline/AnalyticsTimelineGridViews.swift"
        ]
            .map(sourceText)
            .joined(separator: "\n")
        let analyticsSource = try [
            "timetracker/Models/AnalyticsReadModels.swift",
            "timetracker/Services/Analytics/HourTaskActivityService.swift",
            "timetracker/Services/Analytics/AnalyticsTimelineSnapshotService.swift",
            "timetracker/Services/Analytics/HourStackLayoutEngine.swift"
        ]
            .map(sourceText)
            .joined(separator: "\n")
        let combinedSource = viewSource + "\n" + analyticsSource
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(entrySource.contains("TodayActivityContent(activity: snapshot.todayActivity)"))
        #expect(entrySource.contains("OverlappingTimelineContent(timeline: snapshot.timeline)"))
        #expect(viewSource.contains("private var hourly") == false)
        #expect(viewSource.contains("@ObservedObject var store") == false)
        #expect(viewSource.contains("TimelineLayoutEngine.layout(") == false)
        #expect(combinedSource.contains("struct HourTaskSlice"))
        #expect(combinedSource.contains("struct AnalyticsTimelineSnapshot"))
        #expect(combinedSource.contains("Color(hex: colorHex)"))
        #expect(combinedSource.contains("AnalyticsLegendSwatch(color: .blue, title: AppStrings.wallTime)") == false)
        #expect(combinedSource.contains("HourStackLayoutEngine.layout"))
        #expect(combinedSource.contains("RoundedRectangle(cornerRadius: cornerRadius"))
        #expect(combinedSource.contains("availableHeight * CGFloat(point.totalSeconds)") == false)
        #expect(combinedSource.contains(".clipShape(Capsule())") == false)
        #expect(englishStrings.contains("\"analytics.hourDistribution.taskColorHint\""))
    }

    @Test
    func hourStackLayoutPreservesTinyTasksByBorrowingFromLargestSlice() throws {
        let largeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let tinyID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let smallerID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

        let layout = HourStackLayoutEngine.layout(
            inputs: [
                HourStackLayoutInput(id: largeID, seconds: 3_500),
                HourStackLayoutInput(id: tinyID, seconds: 10),
                HourStackLayoutInput(id: smallerID, seconds: 10)
            ],
            availableHeight: 100,
            minSliceHeight: 8
        )

        let large = try #require(layout.first { $0.id == largeID })
        let tiny = try #require(layout.first { $0.id == tinyID })
        let smaller = try #require(layout.first { $0.id == smallerID })

        #expect(layout.count == 3)
        #expect(tiny.height == 8)
        #expect(smaller.height == 8)
        #expect(large.height > 80)
        #expect(abs(layout.reduce(0) { $0 + $1.height } - 100) < 0.001)
    }

    @Test
    func hourStackLayoutDropsShortestTasksWhenMinimumHeightsWouldOverflow() {
        let ids = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000016")!
        ]

        let layout = HourStackLayoutEngine.layout(
            inputs: zip(ids, [100, 90, 80, 70, 60, 50]).map { id, seconds in
                HourStackLayoutInput(id: id, seconds: seconds)
            },
            availableHeight: 50,
            minSliceHeight: 10
        )

        #expect(layout.count == 4)
        #expect(layout.map(\.id) == Array(ids.prefix(4)))
        #expect(layout.contains { $0.id == ids[4] } == false)
        #expect(layout.contains { $0.id == ids[5] } == false)
        #expect(abs(layout.reduce(0) { $0 + $1.height } - 50) < 0.001)
    }

    @Test @MainActor
    func monthAnalyticsUsesUniqueDayNumberLabels() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 28, hour: 12)))
        let points = AnalyticsEngine().dailyBreakdown(segments: [], range: .month, now: now, calendar: calendar)

        #expect(points.count == 28)
        #expect(Set(points.map(\.label)).count == points.count)
        #expect(points.first?.label == "1")
        #expect(points.last?.label == "28")
    }

    @Test @MainActor
    func monthAnalyticsOmitsFutureDaysButPreservesCompleteHistoricalPeriods() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let currentCutoff = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 28,
            hour: 12
        )))
        let period = try #require(AnalyticsRange.month.interval(
            containing: currentCutoff,
            calendar: calendar
        ))
        let futureReference = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 15
        )))
        let futurePeriod = try #require(AnalyticsRange.month.interval(
            containing: futureReference,
            calendar: calendar
        ))
        var store = AnalyticsStore()

        let current = store.cachedDailyBreakdown(
            segments: [],
            range: .month,
            interval: period,
            evaluatedAt: currentCutoff,
            calendar: calendar
        )
        let completed = store.cachedDailyBreakdown(
            segments: [],
            range: .month,
            interval: period,
            evaluatedAt: period.end,
            calendar: calendar
        )
        let future = store.dailyBreakdown(
            segments: [],
            range: .month,
            interval: futurePeriod,
            evaluatedAt: futurePeriod.start,
            calendar: calendar
        )

        #expect(current.count == 28)
        #expect(completed.count == 30)
        #expect(completed.last?.label == "30")
        #expect(future.isEmpty)
        #expect(store.ledgerBucketCount == 30)
    }

    @Test
    func dailyAnalyticsMinutesRetainSubminutePrecision() {
        let point = DailyAnalyticsPoint(
            date: Date(timeIntervalSince1970: 0),
            grossSeconds: 30,
            wallSeconds: 15,
            label: "1"
        )

        #expect(point.grossMinutes == 0.5)
        #expect(point.wallMinutes == 0.25)
    }
}

private func fixedAnalyticsMidday() -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 12, minute: 0))!
}
