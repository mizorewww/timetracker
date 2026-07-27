import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct AnalyticsTimelineTests {
    @Test @MainActor
    func analyticsOverviewBreakdownAndOverlapIgnoreLegacyTaskStatusRaw() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "Coding", parentID: nil, colorHex: "1677FF", iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Meeting", parentID: nil, colorHex: "EF4444", iconName: nil)
        firstTask.statusRaw = LegacyTaskStatusRaw.completed
        secondTask.statusRaw = LegacyTaskStatusRaw.planned
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
        #expect(overview.grossSeconds == 7200)
        #expect(overview.wallSeconds == 5400)
        #expect(overview.overlapSeconds == 1800)

        let tasks = store.taskBreakdown(range: .week, now: now)
        #expect(tasks.count == 2)
        #expect(tasks.first?.grossSeconds == 3600)
        #expect(tasks.map(\.taskID).contains(firstTask.id))
        #expect(tasks.map(\.taskID).contains(secondTask.id))

        let overlaps = store.overlapSegments(range: .week, now: now)
        #expect(overlaps.first?.wallDurationSeconds == 1800)
        #expect(overlaps.first?.excessDurationSeconds == 1800)
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
            startedAt: startOfDay.addingTimeInterval(9 * 3600 + 30 * 60),
            endedAt: startOfDay.addingTimeInterval(10 * 3600 + 15 * 60),
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
            startedAt: startOfDay.addingTimeInterval(9 * 3600),
            endedAt: startOfDay.addingTimeInterval(10 * 3600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: secondTask.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3600 + 30 * 60),
            endedAt: startOfDay.addingTimeInterval(10 * 3600),
            note: nil
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let nine = store.hourlyBreakdown(for: now, now: now)[9]

        #expect(nine.grossSeconds == 90 * 60)
        #expect(nine.wallSeconds == 60 * 60)
    }

    @Test @MainActor
    func taskBreakdownKeepsLedgerVisibleAfterTaskTombstone() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Client Research", parentID: nil, colorHex: "1677FF", iconName: nil)
        let now = fixedAnalyticsMidday()

        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now.addingTimeInterval(-1800),
            note: "Billable"
        )
        let tombstonedAt = task.updatedAt.addingTimeInterval(1)
        task.deletedAt = tombstonedAt
        task.updatedAt = tombstonedAt
        task.deviceID = "legacy-sync"
        task.clientMutationID = UUID()
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let breakdown = store.taskBreakdown(range: .today, now: now)

        #expect(breakdown.count == 1)
        #expect(breakdown.first?.title == "Client Research")
        #expect(breakdown.first?.path == AppStrings.localized("task.unavailable.path"))
        #expect(breakdown.first?.grossSeconds == 1800)
    }

    @Test @MainActor
    func analyticsDecisionSnapshotBuildsComparisonRhythmQualityAndGroups() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 12)))
        let startOfDay = calendar.startOfDay(for: now)
        let previousDay = startOfDay.addingTimeInterval(-86400)
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
                startedAt: startOfDay.addingTimeInterval(9 * 3600),
                endedAt: startOfDay.addingTimeInterval(10 * 3600)
            ),
            TimeSegment(
                sessionID: childSession.id,
                taskID: child.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(9 * 3600 + 50 * 60),
                endedAt: startOfDay.addingTimeInterval(10 * 3600 + 10 * 60)
            ),
            TimeSegment(
                sessionID: childSession.id,
                taskID: child.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(11 * 3600),
                endedAt: startOfDay.addingTimeInterval(11 * 3600 + 120)
            ),
            TimeSegment(
                sessionID: previousSession.id,
                taskID: root.id,
                source: .timer,
                deviceID: "test",
                startedAt: previousDay.addingTimeInterval(9 * 3600),
                endedAt: previousDay.addingTimeInterval(9 * 3600 + 30 * 60)
            ),
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

        #expect(snapshot.comparison.previousGrossSeconds == 1800)
        #expect(snapshot.comparison.currentGrossSeconds == 4920)
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
                startedAt: yesterdayStart.addingTimeInterval(9 * 3600),
                endedAt: yesterdayStart.addingTimeInterval(10 * 3600)
            ),
            TimeSegment(
                sessionID: session.id,
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: todayStart.addingTimeInterval(9 * 3600),
                endedAt: todayStart.addingTimeInterval(9 * 3600 + 30 * 60)
            ),
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

        #expect(yesterdaySnapshot.overview.grossSeconds == 3600)
        #expect(todaySnapshot.overview.grossSeconds == 1800)
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
                startedAt: startOfDay.addingTimeInterval(8 * 3600),
                endedAt: startOfDay.addingTimeInterval(9 * 3600)
            ),
            TimeSegment(
                sessionID: childSession.id,
                taskID: child.id,
                source: .timer,
                deviceID: "test",
                startedAt: startOfDay.addingTimeInterval(10 * 3600),
                endedAt: startOfDay.addingTimeInterval(10 * 3600 + 30 * 60)
            ),
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

        #expect(snapshot.overview.grossSeconds == 5400)
        #expect(snapshot.directSeconds == 3600)
        #expect(snapshot.descendantSeconds == 1800)
        #expect(snapshot.childBreakdown.map(\.title).contains("Build"))
        #expect(snapshot.childBreakdown.map(\.title).contains("Tests"))
        #expect(snapshot.recentRecords.count == 2)
    }

    @Test @MainActor
    func taskAnalyticsRequestAndCacheIgnoreUnrelatedLiveTimersButIncludeDescendants() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 17,
            hour: 12,
            minute: 30
        )))
        let root = TaskNode(title: "Root", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Child", parentID: root.id, deviceID: "test")
        let unrelated = TaskNode(title: "Unrelated", parentID: nil, deviceID: "test")
        let childSession = TimeSession(
            taskID: child.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-1800)
        )
        let unrelatedSession = TimeSession(
            taskID: unrelated.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-3600)
        )
        let childSegment = TimeSegment(
            sessionID: childSession.id,
            taskID: child.id,
            source: .timer,
            deviceID: "test",
            startedAt: childSession.startedAt
        )
        let unrelatedSegment = TimeSegment(
            sessionID: unrelatedSession.id,
            taskID: unrelated.id,
            source: .timer,
            deviceID: "test",
            startedAt: unrelatedSession.startedAt
        )
        let store = makeTestStore()
        store.tasks = [root, child, unrelated]
        store.sessions = [childSession, unrelatedSession]
        store.allSegments = [childSegment, unrelatedSegment]
        store.activeSegments = [unrelatedSegment]

        let unrelatedOnlyRequest = store.taskAnalyticsSnapshotRequest(
            for: root,
            range: .today,
            now: now,
            calendar: calendar
        )
        let globalBucket = try #require(store.analyticsLiveRefreshBucket(
            for: .today,
            now: now,
            calendar: calendar
        ))

        #expect(unrelatedOnlyRequest.taskIDs == [root.id, child.id])
        #expect(unrelatedOnlyRequest.liveRefreshBucket == nil)
        _ = try #require(store.taskAnalyticsSnapshot(
            for: unrelatedOnlyRequest,
            now: now,
            calendar: calendar
        ))
        #expect(store.analyticsDomainStore.cachedTaskSnapshot(
            taskID: root.id,
            range: .today,
            now: now,
            liveRefreshBucket: nil,
            calendar: calendar
        ) != nil)
        #expect(store.analyticsDomainStore.cachedTaskSnapshot(
            taskID: root.id,
            range: .today,
            now: now,
            liveRefreshBucket: globalBucket,
            calendar: calendar
        ) == nil)

        store.activeSegments = [childSegment, unrelatedSegment]
        let descendantRequest = store.taskAnalyticsSnapshotRequest(
            for: root,
            range: .today,
            now: now,
            calendar: calendar
        )
        let descendantSnapshot = try #require(store.taskAnalyticsSnapshot(
            for: descendantRequest,
            now: now,
            calendar: calendar
        ))

        #expect(descendantRequest.liveRefreshBucket == globalBucket)
        #expect(descendantSnapshot.overview.grossSeconds == 1800)
        #expect(descendantSnapshot.descendantSeconds == 1800)
        #expect(store.analyticsDomainStore.cachedTaskSnapshot(
            taskID: root.id,
            range: .today,
            now: now,
            liveRefreshBucket: descendantRequest.liveRefreshBucket,
            calendar: calendar
        ) != nil)
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
    func timelineChartCentersLaneGroupsInsideEachPlotArea() {
        let vertical = TimelineChartLayout.verticalLanes(
            width: 340,
            laneCount: 1
        )
        let axisWidth = TimelineChartLayout.verticalAxisLabelWidth
        let trailingInset = TimelineChartLayout.verticalTrailingInset
        let verticalPlotMidpoint: CGFloat =
            axisWidth + (340 - axisWidth - trailingInset) / 2
        #expect(abs(vertical.midpoint - verticalPlotMidpoint) < 0.001)

        let verticalOverlap = TimelineChartLayout.verticalLanes(
            width: 340,
            laneCount: 3
        )
        #expect(abs(verticalOverlap.midpoint - verticalPlotMidpoint) < 0.001)
        #expect(verticalOverlap.origin >= axisWidth)
        #expect(
            verticalOverlap.origin + verticalOverlap.groupExtent
                <= 340 - trailingInset
        )

        let horizontal = TimelineChartLayout.horizontalLanes(
            height: TimelineChartLayout.horizontalTimelineHeight(
                laneCount: 1,
                gapLabelRowCount: 0
            ),
            laneCount: 1,
            gapLabelRowCount: 0
        )
        let horizontalPlotHeight = TimelineChartLayout.horizontalPlotHeight(
            height: TimelineChartLayout.horizontalTimelineHeight(
                laneCount: 1,
                gapLabelRowCount: 0
            ),
            gapLabelRowCount: 0
        )
        #expect(abs(horizontal.midpoint - horizontalPlotHeight / 2) < 0.001)

        let horizontalOverlapHeight = TimelineChartLayout.horizontalTimelineHeight(
            laneCount: 3,
            gapLabelRowCount: 0
        )
        let horizontalOverlap = TimelineChartLayout.horizontalLanes(
            height: horizontalOverlapHeight,
            laneCount: 3,
            gapLabelRowCount: 0
        )
        let horizontalOverlapPlotHeight = TimelineChartLayout.horizontalPlotHeight(
            height: horizontalOverlapHeight,
            gapLabelRowCount: 0
        )
        #expect(
            abs(horizontalOverlap.midpoint - horizontalOverlapPlotHeight / 2) < 0.001
        )
        #expect(horizontalOverlap.origin >= 0)
        #expect(
            horizontalOverlap.origin + horizontalOverlap.groupExtent
                <= horizontalOverlapPlotHeight
        )

        #expect(
            TimelineChartLayout.axisLabelOrigin(
                position: 0,
                axisLength: 340,
                labelExtent: 52,
                role: .start
            ) == 0
        )
        #expect(
            TimelineChartLayout.axisLabelOrigin(
                position: 170,
                axisLength: 340,
                labelExtent: 52,
                role: .interior
            ) == 144
        )
        #expect(
            TimelineChartLayout.axisLabelOrigin(
                position: 340,
                axisLength: 340,
                labelExtent: 52,
                role: .end
            ) == 288
        )
    }

    @Test
    func horizontalTimelineAssignsLanesFromRenderedFootprints() throws {
        let start = Date(timeIntervalSince1970: 0)
        let display = DateInterval(start: start, duration: 5430)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000112")!
        let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000113")!
        let entries = [
            makeTimelineEntry(
                id: firstID,
                start: start,
                end: start.addingTimeInterval(30)
            ),
            makeTimelineEntry(
                id: secondID,
                start: start.addingTimeInterval(120),
                end: start.addingTimeInterval(150)
            ),
            makeTimelineEntry(
                id: thirdID,
                start: start.addingTimeInterval(600),
                end: start.addingTimeInterval(630)
            ),
        ]
        let compression = TimelineAxisCompression(
            displayInterval: display,
            busyIntervals: entries.map(\.interval)
        )

        let layout = TimelineChartLayout.horizontalBars(
            entries: entries,
            compression: compression,
            width: 720
        )
        let first = try #require(
            layout.placements.first { $0.id == .trackedSegment(firstID) }
        )
        let second = try #require(
            layout.placements.first { $0.id == .trackedSegment(secondID) }
        )
        let third = try #require(
            layout.placements.first { $0.id == .trackedSegment(thirdID) }
        )

        #expect(layout.axisLength == 700)
        #expect(layout.laneCount == 2)
        #expect(first.lane == 0)
        #expect(second.lane == 1)
        #expect(third.lane == 0)
        #expect(first.axisExtent == 20)
        #expect(second.axisOrigin - first.axisEnd < 6)
        #expect(third.axisOrigin - first.axisEnd > 6)
        #expect(
            TimelineChartLayout.horizontalBars(
                entries: Array(entries.reversed()),
                compression: compression,
                width: 720
            ) == layout
        )
    }

    @Test
    func horizontalTimelineReservesTerminalMarkAndHandlesZeroWidth() throws {
        let start = Date(timeIntervalSince1970: 0)
        let display = DateInterval(start: start, duration: 60 * 60)
        let entry = makeTimelineEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000114")!,
            start: start.addingTimeInterval(59 * 60),
            end: display.end
        )
        let compression = TimelineAxisCompression(
            displayInterval: display,
            busyIntervals: [entry.interval]
        )

        let layout = TimelineChartLayout.horizontalBars(
            entries: [entry],
            compression: compression,
            width: 120
        )
        let placement = try #require(layout.placements.first)
        let zero = TimelineChartLayout.horizontalBars(
            entries: [entry],
            compression: compression,
            width: 0
        )

        #expect(layout.axisLength == 100)
        #expect(placement.axisExtent == 20)
        #expect(placement.axisEnd <= 120)
        #expect(placement.axisEnd > layout.axisLength)
        #expect(zero.axisLength == 0)
        #expect(zero.placements.isEmpty)
        #expect(zero.laneCount == 0)
    }

    @Test
    func horizontalTimelineReservesGapAnnotationBandAcrossDenseLanes() {
        let laneCount = 11
        let gapLabelRowCount = 1
        let height = TimelineChartLayout.horizontalTimelineHeight(
            laneCount: laneCount,
            gapLabelRowCount: gapLabelRowCount
        )
        let plotHeight = TimelineChartLayout.horizontalPlotHeight(
            height: height,
            gapLabelRowCount: gapLabelRowCount
        )
        let lanes = TimelineChartLayout.horizontalLanes(
            height: height,
            laneCount: laneCount,
            gapLabelRowCount: gapLabelRowCount
        )
        let startFrame = TimelineChartLayout.horizontalGapLabelFrame(
            placement: TimelineChartHorizontalGapLabelPlacement(
                id: "start",
                row: 0,
                axisOrigin: 0,
                axisExtent: 96
            ),
            plotHeight: plotHeight
        )
        let endFrame = TimelineChartLayout.horizontalGapLabelFrame(
            placement: TimelineChartHorizontalGapLabelPlacement(
                id: "end",
                row: 0,
                axisOrigin: 606,
                axisExtent: 96
            ),
            plotHeight: plotHeight
        )
        let axisLabelTop = TimelineChartLayout.horizontalAxisLabelOrigin(
            plotHeight: plotHeight,
            gapLabelRowCount: gapLabelRowCount
        )

        #expect(lanes.laneExtent == 24)
        #expect(lanes.laneSpacing == 10)
        #expect(lanes.origin + lanes.groupExtent <= plotHeight)
        #expect(startFrame.minX == 0)
        #expect(endFrame.maxX == 702)
        #expect(startFrame.minY >= plotHeight)
        #expect(startFrame.maxY <= axisLabelTop)
        #expect(endFrame.minY >= plotHeight)
        #expect(endFrame.maxY <= axisLabelTop)
    }

    @Test
    func timelineBarsReserveIconAndPaddingAcrossBothAxes() {
        let expectedFootprint =
            TimelineChartLayout.barIconExtent +
            2 * TimelineChartLayout.barIconPadding
        let denseLaneCount = 10
        let minimumWidth = TimelineChartLayout.verticalMinimumContentWidth(
            laneCount: denseLaneCount
        )
        let denseLanes = TimelineChartLayout.verticalLanes(
            width: minimumWidth,
            laneCount: denseLaneCount
        )
        let horizontalLanes = TimelineChartLayout.horizontalLanes(
            height: TimelineChartLayout.horizontalTimelineHeight(
                laneCount: denseLaneCount,
                gapLabelRowCount: 0
            ),
            laneCount: denseLaneCount,
            gapLabelRowCount: 0
        )

        #expect(expectedFootprint == 20)
        #expect(TimelineChartLayout.minimumBarFootprint == expectedFootprint)
        #expect(TimelineChartLayout.horizontalMinimumBarExtent >= expectedFootprint)
        #expect(TimelineChartLayout.verticalMinimumBarExtent >= expectedFootprint)
        #expect(minimumWidth == 380)
        #expect(denseLanes.laneExtent >= expectedFootprint)
        #expect(denseLanes.laneSpacing == TimelineChartLayout.verticalPreferredLaneSpacing)
        #expect(
            denseLanes.origin + denseLanes.groupExtent <=
                minimumWidth - TimelineChartLayout.verticalTrailingInset
        )
        #expect(horizontalLanes.laneExtent >= expectedFootprint)
    }

    @Test
    func horizontalGapAnnotationsUseSeparateRowsAndExpandHeight() throws {
        let start = Date(timeIntervalSince1970: 0)
        let first = DateInterval(start: start, duration: 3 * 60 * 60)
        let middle = DateInterval(
            start: start.addingTimeInterval(5 * 60 * 60),
            duration: 10 * 60
        )
        let last = DateInterval(
            start: start.addingTimeInterval(7 * 60 * 60 + 10 * 60),
            duration: 3 * 60 * 60
        )
        let display = DateInterval(start: first.start, end: last.end)
        let compression = TimelineAxisCompression(
            displayInterval: display,
            busyIntervals: [first, middle, last]
        )
        let labelWidths: [String: CGFloat] = Dictionary(
            uniqueKeysWithValues: zip(
                compression.omittedGaps.map(\.id),
                [72, 148]
            )
        )
        let layout = TimelineChartLayout.horizontalGapLabels(
            gaps: compression.omittedGaps,
            compression: compression,
            axisLength: 702,
            labelWidths: labelWidths
        )

        #expect(compression.omittedGaps.count == 2)
        #expect(layout.placements.count == 2)
        #expect(layout.rowCount == 2)
        #expect(Set(layout.placements.map(\.row)) == Set([0, 1]))
        #expect(
            Dictionary(
                uniqueKeysWithValues: layout.placements.map {
                    ($0.id, $0.axisExtent)
                }
            ) == labelWidths
        )
        #expect(
            TimelineChartLayout.horizontalGapLabels(
                gaps: Array(compression.omittedGaps.reversed()),
                compression: compression,
                axisLength: 702,
                labelWidths: labelWidths
            ) == layout
        )

        let height = TimelineChartLayout.horizontalTimelineHeight(
            laneCount: 3,
            gapLabelRowCount: layout.rowCount
        )
        let oneRowHeight = TimelineChartLayout.horizontalTimelineHeight(
            laneCount: 3,
            gapLabelRowCount: 1
        )
        let plotHeight = TimelineChartLayout.horizontalPlotHeight(
            height: height,
            gapLabelRowCount: layout.rowCount
        )
        let firstPlacement = try #require(layout.placements.first)
        let secondPlacement = try #require(layout.placements.dropFirst().first)
        let firstFrame = TimelineChartLayout.horizontalGapLabelFrame(
            placement: firstPlacement,
            plotHeight: plotHeight
        )
        let secondFrame = TimelineChartLayout.horizontalGapLabelFrame(
            placement: secondPlacement,
            plotHeight: plotHeight
        )
        let horizontalOverlap = min(firstFrame.maxX, secondFrame.maxX) -
            max(firstFrame.minX, secondFrame.minX)
        let axisLabelTop = TimelineChartLayout.horizontalAxisLabelOrigin(
            plotHeight: plotHeight,
            gapLabelRowCount: layout.rowCount
        )

        #expect(horizontalOverlap > 0)
        #expect(firstFrame.intersects(secondFrame) == false)
        #expect(
            height - oneRowHeight ==
                TimelineChartLayout.horizontalGapLabelHeight +
                TimelineChartLayout.horizontalGapLabelRowSpacing
        )
        #expect(max(firstFrame.maxY, secondFrame.maxY) <= axisLabelTop)

        let measuredLabelHeight: CGFloat = 38
        let oneRowAnnotationHeight = TimelineChartLayout.horizontalGapAnnotationHeight(
            rowCount: 1,
            labelHeight: measuredLabelHeight
        )
        let twoRowAnnotationHeight = TimelineChartLayout.horizontalGapAnnotationHeight(
            rowCount: 2,
            labelHeight: measuredLabelHeight
        )
        let measuredTimelineHeight = TimelineChartLayout.horizontalTimelineHeight(
            laneCount: 3,
            gapLabelRowCount: 2,
            gapLabelHeight: measuredLabelHeight
        )
        let measuredOneRowTimelineHeight = TimelineChartLayout.horizontalTimelineHeight(
            laneCount: 3,
            gapLabelRowCount: 1,
            gapLabelHeight: measuredLabelHeight
        )

        #expect(
            twoRowAnnotationHeight - oneRowAnnotationHeight ==
                measuredLabelHeight + TimelineChartLayout.horizontalGapLabelRowSpacing
        )
        #expect(
            measuredTimelineHeight - measuredOneRowTimelineHeight ==
                measuredLabelHeight + TimelineChartLayout.horizontalGapLabelRowSpacing
        )

        let narrowAxisLayout = TimelineChartLayout.horizontalGapLabels(
            gaps: [compression.omittedGaps[1]],
            compression: compression,
            axisLength: 100,
            labelWidths: [compression.omittedGaps[1].id: 148]
        )
        #expect(narrowAxisLayout.placements.first?.axisExtent == 148)
        #expect(
            TimelineChartLayout.horizontalMinimumContentWidth(
                availableWidth: 100,
                gapLabelWidths: [72, 148]
            ) == 148 + TimelineChartLayout.horizontalMinimumBarExtent
        )
    }

    @Test
    func compactTimelineGutterHugsTheLongestGapCapsule() {
        let gapLabelWidths: [CGFloat] = [72, 148]
        let axisLabelWidth = TimelineChartLayout.verticalAxisLabelWidth(
            for: gapLabelWidths
        )
        let baselineMinimumWidth = TimelineChartLayout.verticalMinimumContentWidth(
            laneCount: 3
        )
        let contentSizedMinimumWidth = TimelineChartLayout.verticalMinimumContentWidth(
            laneCount: 3,
            axisLabelWidth: axisLabelWidth
        )
        let lanes = TimelineChartLayout.verticalLanes(
            width: contentSizedMinimumWidth,
            laneCount: 3,
            axisLabelWidth: axisLabelWidth
        )

        #expect(
            TimelineChartLayout.verticalAxisLabelWidth(for: []) ==
                TimelineChartLayout.verticalAxisLabelWidth
        )
        #expect(
            axisLabelWidth == gapLabelWidths.max()! +
                2 * TimelineChartLayout.verticalGapLabelHorizontalInset
        )
        #expect(axisLabelWidth > TimelineChartLayout.verticalAxisLabelWidth)
        #expect(
            contentSizedMinimumWidth - baselineMinimumWidth ==
                axisLabelWidth - TimelineChartLayout.verticalAxisLabelWidth
        )
        #expect(lanes.origin >= axisLabelWidth)
        #expect(
            lanes.origin + lanes.groupExtent <=
                contentSizedMinimumWidth - TimelineChartLayout.verticalTrailingInset
        )
    }

    @Test
    func compactVerticalGapAnnotationsResolveDenseCollisionsDeterministically() throws {
        let start = Date(timeIntervalSince1970: 0)
        let first = DateInterval(start: start, duration: 3 * 60 * 60)
        let middle = DateInterval(
            start: start.addingTimeInterval(5 * 60 * 60),
            duration: 10 * 60
        )
        let last = DateInterval(
            start: start.addingTimeInterval(7 * 60 * 60 + 10 * 60),
            duration: 110 * 60
        )
        let display = DateInterval(start: first.start, end: last.end)
        let compression = TimelineAxisCompression(
            displayInterval: display,
            busyIntervals: [first, middle, last]
        )
        let axisLength: CGFloat = 300
        let rawFrames = compression.omittedGaps.map { gap in
            TimelineChartLayout.verticalGapLabelFrame(
                position: axisLength * CGFloat(
                    compression.ratio(
                        forCompressedOffset: gap.compressedMidpointOffset
                    )
                ),
                axisLength: axisLength
            )
        }
        let layout = TimelineChartLayout.verticalGapLabels(
            gaps: compression.omittedGaps,
            compression: compression,
            axisLength: axisLength
        )
        let frames = layout.placements.map {
            TimelineChartLayout.verticalGapLabelFrame(placement: $0)
        }

        #expect(compression.omittedGaps.count == 2)
        #expect(rawFrames[0].intersects(rawFrames[1]))
        #expect(layout.placements.count == 2)
        #expect(layout.hiddenCount == 0)
        #expect(
            TimelineChartLayout.verticalGapLabels(
                gaps: Array(compression.omittedGaps.reversed()),
                compression: compression,
                axisLength: axisLength
            ) == layout
        )
        #expect(frames[0].intersects(frames[1]) == false)
        #expect(
            frames[1].minY - frames[0].maxY >=
                TimelineChartLayout.verticalGapLabelMinimumSpacing
        )
        #expect(frames.allSatisfy { frame in
            frame.minY >= TimelineChartLayout.verticalGapLabelBoundaryInset &&
                frame.maxY <= axisLength - TimelineChartLayout.verticalGapLabelBoundaryInset
        })
        #expect(
            layout.placements[0].anchorPosition <
                layout.placements[1].anchorPosition
        )

        let constrained = TimelineChartLayout.verticalGapLabels(
            gaps: compression.omittedGaps,
            compression: compression,
            axisLength: 100
        )
        let constrainedFrame = try #require(
            constrained.placements.first.map {
                TimelineChartLayout.verticalGapLabelFrame(placement: $0)
            }
        )
        #expect(constrained.placements.count == 1)
        #expect(constrained.hiddenCount == 1)
        #expect(constrainedFrame.height == TimelineChartLayout.verticalGapLabelHeight)
        #expect(constrainedFrame.minY >= TimelineChartLayout.verticalGapLabelBoundaryInset)
        #expect(constrainedFrame.maxY <= 100 - TimelineChartLayout.verticalGapLabelBoundaryInset)
    }

    @Test
    func compactVerticalGapAnnotationCapacityExpandsTimeline() {
        let count = 12
        let height = TimelineChartLayout.verticalTimelineHeight(
            minimumHeight: 320,
            gapLabelCount: count
        )
        let axisLength = height - TimelineChartLayout.verticalMinimumBarExtent
        let requiredFootprint =
            2 * TimelineChartLayout.verticalGapLabelBoundaryInset +
            CGFloat(count) * TimelineChartLayout.verticalGapLabelHeight +
            CGFloat(count - 1) * TimelineChartLayout.verticalGapLabelMinimumSpacing

        #expect(height > 320)
        #expect(axisLength >= requiredFootprint)
        #expect(
            TimelineChartLayout.verticalTimelineHeight(
                minimumHeight: 320,
                gapLabelCount: 0
            ) == 320
        )
    }

    @Test
    func compactVerticalTimelineAssignsLanesFromRenderedFootprints() throws {
        let start = Date(timeIntervalSince1970: 0)
        let display = DateInterval(start: start, duration: 60 * 60)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let entries = [
            makeTimelineEntry(
                id: firstID,
                start: start,
                end: start.addingTimeInterval(60)
            ),
            makeTimelineEntry(
                id: secondID,
                start: start.addingTimeInterval(4 * 60),
                end: start.addingTimeInterval(5 * 60)
            ),
            makeTimelineEntry(
                id: thirdID,
                start: start.addingTimeInterval(20 * 60),
                end: start.addingTimeInterval(21 * 60)
            ),
        ]
        let compression = TimelineAxisCompression(
            displayInterval: display,
            busyIntervals: entries.map(\.interval)
        )

        let layout = TimelineChartLayout.verticalBars(
            entries: entries,
            compression: compression,
            height: 120
        )
        let first = try #require(
            layout.placements.first { $0.id == .trackedSegment(firstID) }
        )
        let second = try #require(
            layout.placements.first { $0.id == .trackedSegment(secondID) }
        )
        let third = try #require(
            layout.placements.first { $0.id == .trackedSegment(thirdID) }
        )

        #expect(layout.axisLength == 100)
        #expect(layout.laneCount == 2)
        #expect(first.lane == 0)
        #expect(second.lane == 1)
        #expect(third.lane == 0)
        #expect(first.axisExtent == 20)
        #expect(second.axisOrigin - first.axisEnd < 6)
        #expect(third.axisOrigin - first.axisEnd > 6)
        #expect(
            TimelineChartLayout.verticalBars(
                entries: Array(entries.reversed()),
                compression: compression,
                height: 120
            ) == layout
        )
    }

    @Test
    func visualLaneAllocatorReusesLaneAtExactPointThreshold() {
        let firstID = TimelineEntryID.trackedSegment(
            UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
        )
        let secondID = TimelineEntryID.trackedSegment(
            UUID(uuidString: "00000000-0000-0000-0000-000000000106")!
        )
        let intervals = [
            TimelineLaneInterval(id: firstID, start: 0, end: 20),
            TimelineLaneInterval(id: secondID, start: 26, end: 30),
        ]

        #expect(
            TimelineLaneAllocator.assignments(
                for: intervals,
                minimumGap: 6
            ).map(\.lane) == [0, 1]
        )
        #expect(
            TimelineLaneAllocator.assignments(
                for: intervals,
                minimumGap: 6,
                allowsReuseAtMinimumGap: true
            ).map(\.lane) == [0, 0]
        )
    }

    @Test
    func compactVerticalTimelineReturnsNoInvisibleLanesAtZeroHeight() {
        let start = Date(timeIntervalSince1970: 0)
        let entry = makeTimelineEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000107")!,
            start: start,
            end: start.addingTimeInterval(60)
        )
        let compression = TimelineAxisCompression(
            displayInterval: entry.interval,
            busyIntervals: [entry.interval]
        )

        let layout = TimelineChartLayout.verticalBars(
            entries: [entry],
            compression: compression,
            height: 0
        )

        #expect(layout.axisLength == 0)
        #expect(layout.placements.isEmpty)
        #expect(layout.laneCount == 0)
    }

    @Test
    func compactVerticalTimelineAnchorsTerminalShortBarDownward() throws {
        let start = Date(timeIntervalSince1970: 0)
        let display = DateInterval(start: start, duration: 60 * 60)
        let entry = makeTimelineEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
            start: start.addingTimeInterval(59 * 60),
            end: display.end
        )
        let compression = TimelineAxisCompression(
            displayInterval: display,
            busyIntervals: [entry.interval]
        )

        let layout = TimelineChartLayout.verticalBars(
            entries: [entry],
            compression: compression,
            height: 120
        )
        let placement = try #require(layout.placements.first)
        let projectedStart = layout.axisLength * CGFloat(59.0 / 60.0)

        #expect(abs(placement.axisOrigin - projectedStart) < 0.001)
        #expect(placement.axisExtent == 20)
        #expect(placement.axisEnd <= 120)
        #expect(placement.axisEnd > layout.axisLength)
        #expect(placement.axisOrigin != 120 - placement.axisExtent)
    }

    @Test
    func compactVerticalGapLabelStaysInsideAxisGutter() {
        let frame = TimelineChartLayout.verticalGapLabelFrame(
            position: 298,
            axisLength: 300
        )
        let lanes = TimelineChartLayout.verticalLanes(
            width: 340,
            laneCount: 3
        )

        #expect(frame.minX >= 0)
        #expect(frame.maxX <= TimelineChartLayout.verticalAxisLabelWidth)
        #expect(frame.maxX <= lanes.origin)
        #expect(frame.minY >= 0)
        #expect(frame.maxY <= 300)
    }

    @Test
    func compactVerticalTicksYieldToCompressedGapAnnotations() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 22,
            hour: 9
        )))
        let first = DateInterval(start: start, duration: 60 * 60)
        let second = DateInterval(
            start: start.addingTimeInterval(5 * 60 * 60),
            duration: 60 * 60
        )
        let display = DateInterval(start: first.start, end: second.end)
        let compression = TimelineAxisCompression(
            displayInterval: display,
            busyIntervals: [first, second]
        )

        let ticks = TimelineChartLayout.verticalAxisTicks(
            displayInterval: display,
            compression: compression,
            axisLength: 300,
            minimumSpacing: 28,
            calendar: calendar
        )

        #expect(compression.omittedGaps.count == 1)
        #expect(ticks.map(\.date) == [display.start, display.end])
        #expect(ticks.map(\.role) == [.start, .end])
    }

    @Test
    func compactVerticalLanesUseCompressedGapPixelDistance() {
        let start = Date(timeIntervalSince1970: 0)
        let first = makeTimelineEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000108")!,
            start: start,
            end: start.addingTimeInterval(60 * 60)
        )
        let second = makeTimelineEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000109")!,
            start: start.addingTimeInterval(5 * 60 * 60),
            end: start.addingTimeInterval(6 * 60 * 60)
        )
        let display = DateInterval(start: first.startedAt, end: second.endedAt)
        let compression = TimelineAxisCompression(
            displayInterval: display,
            busyIntervals: [first.interval, second.interval]
        )

        let layout = TimelineChartLayout.verticalBars(
            entries: [first, second],
            compression: compression,
            height: 60
        )

        #expect(compression.omittedGaps.count == 1)
        #expect(layout.placements.map(\.lane) == [0, 1])
    }

    @Test
    func timelineChartTicksPreserveExactBoundsWithoutCrowdingNearbyHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 18,
                    hour: 9,
                    minute: 55
                )
            )
        )
        let eleven = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 18,
                    hour: 11
                )
            )
        )
        let end = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 18,
                    hour: 12,
                    minute: 5
                )
            )
        )
        let interval = DateInterval(start: start, end: end)
        let compression = TimelineAxisCompression(
            displayInterval: interval,
            busyIntervals: [interval]
        )

        let ticks = TimelineChartLayout.axisTicks(
            displayInterval: interval,
            compression: compression,
            axisLength: 340,
            minimumSpacing: 28,
            calendar: calendar
        )

        #expect(ticks.map(\.date) == [start, eleven, end])
        #expect(ticks.map(\.role) == [.start, .interior, .end])

        let shortEnd = start.addingTimeInterval(10 * 60)
        let shortInterval = DateInterval(start: start, end: shortEnd)
        let shortTicks = TimelineChartLayout.axisTicks(
            displayInterval: shortInterval,
            compression: TimelineAxisCompression(
                displayInterval: shortInterval,
                busyIntervals: [shortInterval]
            ),
            axisLength: 20,
            minimumSpacing: 28,
            calendar: calendar
        )
        #expect(shortTicks.map(\.date) == [start, shortEnd])
        #expect(shortTicks.first?.role == .start)
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
        #expect(abs((compression.omittedGaps.first?.duration ?? 0) - 14400) < 0.001)
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
        let categorySource = try [
            "timetracker/Features/Analytics/AnalyticsCategoryDetailView.swift",
            "timetracker/Features/Analytics/AnalyticsCategoryDetailContent.swift",
        ].map(sourceText).joined(separator: "\n")
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

    @Test @MainActor
    func todayActivityDistributionUsesTaskColorBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))
        )
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
        let segments = [
            TimeSegment(
                sessionID: UUID(),
                taskID: design.id,
                source: .manual,
                deviceID: "test",
                startedAt: day.addingTimeInterval(9 * 3600),
                endedAt: day.addingTimeInterval(9 * 3600 + 45 * 60)
            ),
            TimeSegment(
                sessionID: UUID(),
                taskID: review.id,
                source: .manual,
                deviceID: "test",
                startedAt: day.addingTimeInterval(9 * 3600 + 15 * 60),
                endedAt: day.addingTimeInterval(10 * 3600)
            ),
        ]

        let activity = HourTaskActivityService().hourlyActivity(
            segments: segments,
            tasks: [design, review],
            sessions: [],
            date: day,
            now: day.addingTimeInterval(12 * 3600),
            calendar: calendar
        )
        let nineOClockSlices = activity[9].slices

        #expect(nineOClockSlices.map(\.taskID) == [design.id, review.id])
        #expect(nineOClockSlices.map(\.colorHex) == ["0A84FF", "FF9F0A"])
        #expect(nineOClockSlices.map(\.seconds) == [45 * 60, 45 * 60])
    }

    @Test
    func hourStackLayoutPreservesTinyTasksByBorrowingFromLargestSlice() throws {
        let largeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let tinyID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let smallerID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

        let layout = HourStackLayoutEngine.layout(
            inputs: [
                HourStackLayoutInput(id: largeID, seconds: 3500),
                HourStackLayoutInput(id: tinyID, seconds: 10),
                HourStackLayoutInput(id: smallerID, seconds: 10),
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
    func hourStackLayoutDropsOnlyTasksBeyondTheVisibleHeightCapacity() {
        let ids = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
        ]

        let layout = HourStackLayoutEngine.layout(
            inputs: zip(ids, [100, 90, 80, 70, 60, 50]).map { id, seconds in
                HourStackLayoutInput(id: id, seconds: seconds)
            },
            availableHeight: 50,
            minSliceHeight: 10
        )

        #expect(layout.count == 5)
        #expect(layout.map(\.id) == Array(ids.prefix(5)))
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

private func makeTimelineEntry(
    id: UUID,
    start: Date,
    end: Date
) -> AnalyticsTimelineEntry {
    AnalyticsTimelineEntry(
        id: .trackedSegment(id),
        subject: .task(id),
        title: "Timeline test",
        path: "Timeline test",
        iconName: "clock",
        colorHex: "1677FF",
        startedAt: start,
        endedAt: end,
        lane: 0,
        labelIndex: 0,
        interval: DateInterval(start: start, end: end),
        durationSeconds: max(0, Int(end.timeIntervalSince(start)))
    )
}
