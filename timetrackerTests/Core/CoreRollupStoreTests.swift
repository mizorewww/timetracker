import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreRollupStoreTests {
    @Test @MainActor
    func rollupStoreOwnsForecastStateSeparatelyFromAnalyticsCache() {
        let task = TaskNode(title: "Rollup Task", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: Date(timeIntervalSince1970: 25_000), titleSnapshot: task.title)
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: session.startedAt,
            endedAt: session.startedAt.addingTimeInterval(900)
        )
        let checklist = [
            ChecklistItem(taskID: task.id, title: "Done", isCompleted: true, sortOrder: 0, deviceID: "test"),
            ChecklistItem(taskID: task.id, title: "Next", isCompleted: false, sortOrder: 1, deviceID: "test")
        ]
        var rollupStore = RollupStore()
        let analyticsStore = AnalyticsStore()

        rollupStore.refresh(tasks: [task], segments: [segment], checklistItems: checklist, now: session.startedAt.addingTimeInterval(1_000))

        #expect(rollupStore.rollup(for: task.id)?.workedSeconds == 900)
        #expect(rollupStore.checklistProgress(for: task.id, checklistItems: checklist).label == "1/2")
        #expect(analyticsStore.cachedSnapshot(for: .today) == nil)
    }

    @Test @MainActor
    func rollupStoreRefreshAffectedRecomputesImpactedBranchAndAncestors() throws {
        let start = Date(timeIntervalSince1970: 30_000)
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let changedChild = TaskNode(title: "Changed Child", parentID: parent.id, deviceID: "test")
        let untouchedChild = TaskNode(title: "Untouched Child", parentID: parent.id, deviceID: "test")
        let changedSession = TimeSession(taskID: changedChild.id, source: .timer, deviceID: "test", startedAt: start)
        let untouchedSession = TimeSession(taskID: untouchedChild.id, source: .timer, deviceID: "test", startedAt: start)
        let changedSegment = TimeSegment(
            sessionID: changedSession.id,
            taskID: changedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(600)
        )
        let untouchedSegment = TimeSegment(
            sessionID: untouchedSession.id,
            taskID: untouchedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(1_200)
        )
        let initialChecklist = [
            ChecklistItem(taskID: changedChild.id, title: "Done", isCompleted: true, sortOrder: 0, deviceID: "test"),
            ChecklistItem(taskID: changedChild.id, title: "Next", isCompleted: false, sortOrder: 1, deviceID: "test"),
            ChecklistItem(taskID: untouchedChild.id, title: "Done", isCompleted: true, sortOrder: 0, deviceID: "test"),
            ChecklistItem(taskID: untouchedChild.id, title: "Next", isCompleted: false, sortOrder: 1, deviceID: "test")
        ]
        var store = RollupStore()
        store.refresh(
            tasks: [parent, changedChild, untouchedChild],
            segments: [changedSegment, untouchedSegment],
            checklistItems: initialChecklist,
            now: start.addingTimeInterval(2_000)
        )

        let initialUntouched = try #require(store.rollup(for: untouchedChild.id))
        #expect(initialUntouched.workedSeconds == 1_200)
        #expect(store.rollup(for: parent.id)?.remainingSeconds == 1_800)

        let staleIfRecomputedSegment = TimeSegment(
            sessionID: untouchedSession.id,
            taskID: untouchedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(7_200)
        )
        let updatedChecklist = initialChecklist + [
            ChecklistItem(taskID: changedChild.id, title: "Later", isCompleted: false, sortOrder: 2, deviceID: "test")
        ]

        store.refreshAffected(
            taskIDs: [changedChild.id],
            tasks: [parent, changedChild, untouchedChild],
            segments: [changedSegment, staleIfRecomputedSegment],
            checklistItems: updatedChecklist,
            now: start.addingTimeInterval(8_000)
        )

        #expect(store.rollup(for: changedChild.id)?.remainingSeconds == 1_200)
        #expect(store.rollup(for: untouchedChild.id) == initialUntouched)
        #expect(store.rollup(for: parent.id)?.remainingSeconds == 2_400)
    }

    @Test @MainActor
    func indexedRefreshMatchesFullRefreshAndUsesNinetyCalendarDayPace() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 14,
            hour: 12
        )))
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let changedChild = TaskNode(title: "Changed", parentID: parent.id, deviceID: "test")
        let untouchedChild = TaskNode(title: "Untouched", parentID: parent.id, deviceID: "test")
        let oldStart = try #require(calendar.date(byAdding: .day, value: -100, to: now))
        let recentStart = try #require(calendar.date(byAdding: .day, value: -2, to: now))
        let oldSegment = TimeSegment(
            sessionID: UUID(),
            taskID: changedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: oldStart,
            endedAt: oldStart.addingTimeInterval(3_600)
        )
        let recentSegment = TimeSegment(
            sessionID: UUID(),
            taskID: changedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: recentStart,
            endedAt: recentStart.addingTimeInterval(1_800)
        )
        let untouchedSegment = TimeSegment(
            sessionID: UUID(),
            taskID: untouchedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: recentStart,
            endedAt: recentStart.addingTimeInterval(900)
        )
        let initialChecklist = [
            ChecklistItem(taskID: changedChild.id, title: "Done", isCompleted: true, sortOrder: 0, deviceID: "test"),
            ChecklistItem(taskID: changedChild.id, title: "Next", isCompleted: false, sortOrder: 1, deviceID: "test")
        ]
        let tasks = [parent, changedChild, untouchedChild]
        var incremental = RollupStore()
        incremental.refresh(
            tasks: tasks,
            segments: [oldSegment, recentSegment, untouchedSegment],
            checklistItems: initialChecklist,
            now: now,
            calendar: calendar
        )
        let untouchedBefore = try #require(incremental.rollup(for: untouchedChild.id))
        let initialChanged = try #require(incremental.rollup(for: changedChild.id))
        #expect(initialChanged.workedSeconds == 5_400)
        #expect(initialChanged.historicalDailyAverageSeconds == 1_800)
        #expect(initialChanged.historicalActiveDayCount == 1)

        let updatedSegment = TimeSegment(
            sessionID: recentSegment.sessionID,
            taskID: changedChild.id,
            source: .timer,
            deviceID: "test",
            startedAt: recentStart,
            endedAt: recentStart.addingTimeInterval(2_700)
        )
        updatedSegment.id = recentSegment.id
        let updatedChecklist = initialChecklist + [
            ChecklistItem(taskID: changedChild.id, title: "Later", isCompleted: false, sortOrder: 2, deviceID: "test")
        ]
        incremental.refreshAffected(
            directTaskIDs: [changedChild.id],
            explicitAncestorTaskIDs: [parent.id],
            segmentChanges: [
                LedgerSegmentChange(
                    id: recentSegment.id,
                    before: LedgerSegmentSnapshot(recentSegment),
                    after: LedgerSegmentSnapshot(updatedSegment)
                )
            ],
            checklistItemsByTaskID: [changedChild.id: updatedChecklist],
            now: now,
            calendar: calendar
        )

        var rebuilt = RollupStore()
        rebuilt.refresh(
            tasks: tasks,
            segments: [oldSegment, updatedSegment, untouchedSegment],
            checklistItems: updatedChecklist,
            now: now,
            calendar: calendar
        )

        #expect(incremental.rollup(for: changedChild.id) == rebuilt.rollup(for: changedChild.id))
        #expect(incremental.rollup(for: parent.id) == rebuilt.rollup(for: parent.id))
        #expect(incremental.rollup(for: untouchedChild.id) == untouchedBefore)
    }

    @Test @MainActor
    func advancingPaceWindowInvalidatesAnOtherwiseUnrelatedTask() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 14,
            hour: 12
        )))
        let expiringTask = TaskNode(title: "Expiring", parentID: nil, deviceID: "test")
        let editedTask = TaskNode(title: "Edited", parentID: nil, deviceID: "test")
        let firstWindowDay = try #require(calendar.date(
            byAdding: .day,
            value: -(RollupIncrementalIndex.historicalPaceDayCount - 1),
            to: calendar.startOfDay(for: now)
        ))
        let expiringSegment = TimeSegment(
            sessionID: UUID(),
            taskID: expiringTask.id,
            source: .timer,
            deviceID: "test",
            startedAt: firstWindowDay.addingTimeInterval(8 * 3_600),
            endedAt: firstWindowDay.addingTimeInterval(9 * 3_600)
        )
        var incremental = RollupStore()
        incremental.refresh(
            tasks: [expiringTask, editedTask],
            segments: [expiringSegment],
            checklistItems: [],
            now: now,
            calendar: calendar
        )
        #expect(incremental.rollup(for: expiringTask.id)?.historicalActiveDayCount == 1)

        let later = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        let editedChecklist = [
            ChecklistItem(taskID: editedTask.id, title: "New", sortOrder: 0, deviceID: "test")
        ]
        incremental.refreshAffected(
            directTaskIDs: [editedTask.id],
            explicitAncestorTaskIDs: [],
            segmentChanges: [],
            checklistItemsByTaskID: [editedTask.id: editedChecklist],
            now: later,
            calendar: calendar
        )

        var rebuilt = RollupStore()
        rebuilt.refresh(
            tasks: [expiringTask, editedTask],
            segments: [expiringSegment],
            checklistItems: editedChecklist,
            now: later,
            calendar: calendar
        )
        #expect(incremental.rollup(for: expiringTask.id) == rebuilt.rollup(for: expiringTask.id))
        #expect(incremental.rollup(for: expiringTask.id)?.historicalActiveDayCount == 0)
        #expect(incremental.rollup(for: expiringTask.id)?.workedSeconds == 3_600)
    }

    @Test @MainActor
    func rewindingPaceWindowRebuildsOtherwiseUnrelatedRollups() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 14,
            hour: 12
        )))
        let earlier = try #require(calendar.date(byAdding: .day, value: -1, to: now))
        let paceTask = TaskNode(title: "Restored Pace", parentID: nil, deviceID: "test")
        let editedTask = TaskNode(title: "Edited", parentID: nil, deviceID: "test")
        let earlierWindowStart = try #require(calendar.date(
            byAdding: .day,
            value: -(RollupIncrementalIndex.historicalPaceDayCount - 1),
            to: calendar.startOfDay(for: earlier)
        ))
        let segment = TimeSegment(
            sessionID: UUID(),
            taskID: paceTask.id,
            source: .timer,
            deviceID: "test",
            startedAt: earlierWindowStart.addingTimeInterval(8 * 3_600),
            endedAt: earlierWindowStart.addingTimeInterval(9 * 3_600)
        )
        var incremental = RollupStore()
        incremental.refresh(
            tasks: [paceTask, editedTask],
            segments: [segment],
            checklistItems: [],
            now: now,
            calendar: calendar
        )
        #expect(incremental.rollup(for: paceTask.id)?.historicalActiveDayCount == 0)

        incremental.refreshAffected(
            directTaskIDs: [editedTask.id],
            explicitAncestorTaskIDs: [],
            segmentChanges: [],
            checklistItemsByTaskID: [:],
            now: earlier,
            calendar: calendar
        )

        var rebuilt = RollupStore()
        rebuilt.refresh(
            tasks: [paceTask, editedTask],
            segments: [segment],
            checklistItems: [],
            now: earlier,
            calendar: calendar
        )
        #expect(incremental.rollup(for: paceTask.id) == rebuilt.rollup(for: paceTask.id))
        #expect(incremental.rollup(for: paceTask.id)?.historicalActiveDayCount == 1)
        #expect(incremental.rollup(for: paceTask.id)?.historicalDailyAverageSeconds == 3_600)
    }

    @Test @MainActor
    func unrelatedRefreshAdvancesOnlyIndexedActiveSegments() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 14,
            hour: 12
        )))
        let activeTask = TaskNode(title: "Active", parentID: nil, deviceID: "test")
        let editedTask = TaskNode(title: "Edited", parentID: nil, deviceID: "test")
        let activeSegment = TimeSegment(
            sessionID: UUID(),
            taskID: activeTask.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-3_600)
        )
        var incremental = RollupStore()
        incremental.refresh(
            tasks: [activeTask, editedTask],
            segments: [activeSegment],
            checklistItems: [],
            now: now,
            calendar: calendar
        )

        let later = now.addingTimeInterval(60)
        let editedChecklist = [
            ChecklistItem(taskID: editedTask.id, title: "New", sortOrder: 0, deviceID: "test")
        ]
        incremental.refreshAffected(
            directTaskIDs: [editedTask.id],
            explicitAncestorTaskIDs: [],
            segmentChanges: [],
            checklistItemsByTaskID: [editedTask.id: editedChecklist],
            now: later,
            calendar: calendar
        )

        var rebuilt = RollupStore()
        rebuilt.refresh(
            tasks: [activeTask, editedTask],
            segments: [activeSegment],
            checklistItems: editedChecklist,
            now: later,
            calendar: calendar
        )
        #expect(incremental.rollup(for: activeTask.id) == rebuilt.rollup(for: activeTask.id))
        #expect(incremental.rollup(for: activeTask.id)?.workedSeconds == 3_660)
    }

    @Test @MainActor
    func calendarChangeRebuildsBoundedDayKeysAndAllPaces() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var plusTwo = utc
        plusTwo.timeZone = try #require(TimeZone(secondsFromGMT: 2 * 3_600))
        let segmentStart = try #require(utc.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13,
            hour: 23,
            minute: 30
        )))
        let now = segmentStart.addingTimeInterval(2 * 3_600)
        let paceTask = TaskNode(title: "Pace", parentID: nil, deviceID: "test")
        let editedTask = TaskNode(title: "Edited", parentID: nil, deviceID: "test")
        let segment = TimeSegment(
            sessionID: UUID(),
            taskID: paceTask.id,
            source: .timer,
            deviceID: "test",
            startedAt: segmentStart,
            endedAt: segmentStart.addingTimeInterval(3_600)
        )
        var incremental = RollupStore()
        incremental.refresh(
            tasks: [paceTask, editedTask],
            segments: [segment],
            checklistItems: [],
            now: now,
            calendar: utc
        )
        #expect(incremental.rollup(for: paceTask.id)?.historicalActiveDayCount == 2)

        incremental.refreshAffected(
            directTaskIDs: [editedTask.id],
            explicitAncestorTaskIDs: [],
            segmentChanges: [],
            checklistItemsByTaskID: [:],
            now: now,
            calendar: plusTwo
        )

        var rebuilt = RollupStore()
        rebuilt.refresh(
            tasks: [paceTask, editedTask],
            segments: [segment],
            checklistItems: [],
            now: now,
            calendar: plusTwo
        )
        #expect(incremental.rollup(for: paceTask.id) == rebuilt.rollup(for: paceTask.id))
        #expect(incremental.rollup(for: paceTask.id)?.historicalActiveDayCount == 1)
        #expect(incremental.rollup(for: paceTask.id)?.historicalDailyAverageSeconds == 3_600)
    }

    @Test @MainActor
    func futureEndedRowsKeepIncrementalRollupsEqualToFullRebuildAcrossClockChanges() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 14,
            hour: 12
        )))
        let trackedTask = TaskNode(title: "Clock skew", parentID: nil, deviceID: "test")
        let editedTask = TaskNode(title: "Refresh trigger", parentID: nil, deviceID: "test")
        let spanningNow = TimeSegment(
            sessionID: UUID(),
            taskID: trackedTask.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-600),
            endedAt: now.addingTimeInterval(600)
        )
        let futureOnly = TimeSegment(
            sessionID: UUID(),
            taskID: trackedTask.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(300),
            endedAt: now.addingTimeInterval(900)
        )
        let tasks = [trackedTask, editedTask]
        let segments = [spanningNow, futureOnly]
        var incremental = RollupStore()
        incremental.refresh(
            tasks: tasks,
            segments: segments,
            checklistItems: [],
            now: now,
            calendar: calendar
        )
        #expect(incremental.rollup(for: trackedTask.id)?.workedSeconds == 600)

        let later = now.addingTimeInterval(600)
        let editedChecklist = [
            ChecklistItem(taskID: editedTask.id, title: "Trigger", sortOrder: 0, deviceID: "test")
        ]
        incremental.refreshAffected(
            directTaskIDs: [editedTask.id],
            explicitAncestorTaskIDs: [],
            segmentChanges: [],
            checklistItemsByTaskID: [editedTask.id: editedChecklist],
            now: later,
            calendar: calendar
        )
        var laterRebuild = RollupStore()
        laterRebuild.refresh(
            tasks: tasks,
            segments: segments,
            checklistItems: editedChecklist,
            now: later,
            calendar: calendar
        )

        #expect(incremental.rollup(for: trackedTask.id) == laterRebuild.rollup(for: trackedTask.id))
        #expect(incremental.rollup(for: trackedTask.id)?.workedSeconds == 1_500)

        let rewound = now.addingTimeInterval(-300)
        incremental.refreshAffected(
            directTaskIDs: [editedTask.id],
            explicitAncestorTaskIDs: [],
            segmentChanges: [],
            checklistItemsByTaskID: [:],
            now: rewound,
            calendar: calendar
        )
        var rewindRebuild = RollupStore()
        rewindRebuild.refresh(
            tasks: tasks,
            segments: segments,
            checklistItems: editedChecklist,
            now: rewound,
            calendar: calendar
        )

        #expect(incremental.rollup(for: trackedTask.id) == rewindRebuild.rollup(for: trackedTask.id))
        #expect(incremental.rollup(for: trackedTask.id)?.workedSeconds == 300)
    }
}
