import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CorePerformanceBudgetTests {
    @Test @MainActor
    func taskTreeFlatteningStaysWithinPerformanceBudget() {
        let roots = (0..<500).map { index in
            TaskNode(title: "Root \(index)", parentID: nil, deviceID: "test")
        }
        let children = roots.enumerated().map { index, root in
            TaskNode(title: "Child \(index)", parentID: root.id, deviceID: "test")
        }
        let childrenByParent = Dictionary(grouping: children) { $0.parentID }
        let expandedIDs = Set(roots.map(\.id))

        let start = CFAbsoluteTimeGetCurrent()
        let rows = TaskTreeFlattener.visibleRows(
            rootTasks: roots,
            children: { task in childrenByParent[Optional(task.id)] ?? [] },
            expandedTaskIDs: expandedIDs
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(rows.count == 1_000)
        #expect(elapsed < 2.0)
    }

    @Test @MainActor
    func analyticsSnapshotStaysWithinPerformanceBudget() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 8)) ?? Date(timeIntervalSince1970: 1_775_000_000)
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 16, hour: 12)) ?? startDate.addingTimeInterval(15 * 24 * 60 * 60)
        let tasks = (0..<40).map { index in
            TaskNode(title: "Analytics Task \(index)", parentID: nil, deviceID: "test")
        }
        let sessions = (0..<720).map { index in
            TimeSession(
                taskID: tasks[index % tasks.count].id,
                source: .timer,
                deviceID: "test",
                startedAt: startDate.addingTimeInterval(Double(index * 1_800)),
                titleSnapshot: tasks[index % tasks.count].title
            )
        }
        let segments = sessions.enumerated().map { index, session in
            TimeSegment(
                sessionID: session.id,
                taskID: session.taskID,
                source: .timer,
                deviceID: "test",
                startedAt: session.startedAt,
                endedAt: session.startedAt.addingTimeInterval(Double(600 + (index % 12) * 60))
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        let snapshot = AnalyticsStore().snapshot(
            range: .month,
            tasks: tasks,
            segments: segments,
            sessions: sessions,
            taskPathByID: Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) }),
            taskParentPathByID: [:],
            now: now,
            calendar: calendar
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(snapshot.daily.isEmpty == false)
        #expect(snapshot.taskBreakdown.isEmpty == false)
        #expect(elapsed < 3.0)
    }

    @Test @MainActor
    func largeLedgerBucketSummariesStayWithinPerformanceBudget() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monthStart = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 0)) ?? Date(timeIntervalSince1970: 1_775_000_000)
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart.addingTimeInterval(31 * 24 * 60 * 60)
        let taskID = UUID()
        let sessions = (0..<20_000).map { index in
            TimeSession(
                taskID: taskID,
                source: .timer,
                deviceID: "test",
                startedAt: monthStart.addingTimeInterval(Double(index * 211))
            )
        }
        let segments = sessions.enumerated().map { index, session in
            TimeSegment(
                sessionID: session.id,
                taskID: taskID,
                source: .timer,
                deviceID: "test",
                startedAt: session.startedAt,
                endedAt: session.startedAt.addingTimeInterval(Double(120 + (index % 9) * 60))
            )
        }
        var cache = LedgerBucketCache()

        let start = CFAbsoluteTimeGetCurrent()
        let summaries = cache.summaries(
            segments: segments,
            interval: DateInterval(start: monthStart, end: monthEnd),
            now: monthEnd,
            calendar: calendar
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(summaries.count == 30)
        #expect(summaries.reduce(0) { $0 + $1.grossSeconds } > 0)
        #expect(cache.bucketCount == 30)
        #expect(elapsed < 2.0)
    }

    @Test @MainActor
    func denseOverlapAnalyticsSnapshotStaysWithinPerformanceBudget() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayStart = calendar.date(from: DateComponents(year: 2026, month: 4, day: 12, hour: 0)) ?? Date(timeIntervalSince1970: 1_776_000_000)
        let now = dayStart.addingTimeInterval(24 * 60 * 60 - 1)
        let tasks = (0..<80).map { index in
            TaskNode(title: "Dense Task \(index)", parentID: nil, deviceID: "test")
        }
        let sessions = (0..<2_000).map { index in
            let task = tasks[index % tasks.count]
            return TimeSession(
                taskID: task.id,
                source: index.isMultiple(of: 7) ? .pomodoro : .timer,
                deviceID: "test",
                startedAt: dayStart.addingTimeInterval(Double(index * 11)),
                titleSnapshot: task.title
            )
        }
        let segments = sessions.enumerated().map { index, session in
            let source: TimeSessionSource = index.isMultiple(of: 7) ? .pomodoro : .timer
            return TimeSegment(
                sessionID: session.id,
                taskID: session.taskID,
                source: source,
                deviceID: "test",
                startedAt: session.startedAt,
                endedAt: min(session.startedAt.addingTimeInterval(Double(1_800 + (index % 15) * 45)), now)
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        let snapshot = AnalyticsStore().snapshot(
            range: .today,
            tasks: tasks,
            segments: segments,
            sessions: sessions,
            taskPathByID: Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0.title) }),
            taskParentPathByID: [:],
            now: now,
            calendar: calendar
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(snapshot.overlaps.isEmpty == false)
        #expect(snapshot.taskBreakdown.count == tasks.count)
        #expect(snapshot.timeline.entries.isEmpty == false)
        #expect(snapshot.todayActivity.contains { $0.totalSeconds > 0 })
        #expect(elapsed < 4.0)
    }

    @Test @MainActor
    func longChecklistRollupStaysWithinPerformanceBudget() {
        let root = TaskNode(title: "Root Forecast", parentID: nil, deviceID: "test")
        let children = (0..<300).map { index in
            TaskNode(title: "Forecast Child \(index)", parentID: root.id, deviceID: "test")
        }
        let tasks = [root] + children
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = children.map { child in
            TimeSession(taskID: child.id, source: .timer, deviceID: "test", startedAt: startDate)
        }
        let segments = sessions.enumerated().map { index, session in
            TimeSegment(
                sessionID: session.id,
                taskID: session.taskID,
                source: .timer,
                deviceID: "test",
                startedAt: startDate,
                endedAt: startDate.addingTimeInterval(Double(1_200 + (index % 6) * 120))
            )
        }
        let checklistItems = children.flatMap { child in
            (0..<40).map { itemIndex in
                ChecklistItem(
                    taskID: child.id,
                    title: "Step \(itemIndex)",
                    isCompleted: itemIndex < 10,
                    sortOrder: Double(itemIndex),
                    deviceID: "test"
                )
            }
        }

        let start = CFAbsoluteTimeGetCurrent()
        let rollups = TaskRollupService().rollups(
            tasks: tasks,
            segments: segments,
            checklistItems: checklistItems,
            now: startDate.addingTimeInterval(86_400)
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(rollups[root.id]?.remainingSeconds ?? 0 > 0)
        #expect(rollups[root.id]?.forecastSourceTaskCount == children.count)
        #expect((rollups[root.id]?.forecastSourceTaskIDs.count ?? 0) <= 32)
        #expect(elapsed < 2.0)
    }

    @Test
    func timelineLayoutWithManyRowsStaysWithinPerformanceBudget() {
        let dayStart = Date(timeIntervalSince1970: 1_800_000_000)
        let day = DateInterval(start: dayStart, duration: 24 * 60 * 60)
        let items = (0..<5_000).map { index in
            let start = dayStart.addingTimeInterval(Double(index * 13))
            return TimelineLayoutItem(
                id: UUID(),
                startedAt: start,
                endedAt: min(start.addingTimeInterval(Double(300 + (index % 11) * 20)), day.end)
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        let layout = TimelineLayoutEngine.layout(items: items, dayInterval: day)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(layout.entries.count == items.count)
        #expect(layout.laneCount > 1)
        #expect(elapsed < 1.0)
    }

    @Test @MainActor
    func affectedRollupRefreshStaysWithinPerformanceBudget() throws {
        let parent = TaskNode(title: "Budget Parent", parentID: nil, deviceID: "test")
        let children = (0..<500).map { index in
            TaskNode(title: "Budget Child \(index)", parentID: parent.id, deviceID: "test")
        }
        let startDate = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = children.map { child in
            TimeSession(taskID: child.id, source: .timer, deviceID: "test", startedAt: startDate)
        }
        let segments = zip(children.indices, sessions).map { index, session in
            TimeSegment(
                sessionID: session.id,
                taskID: session.taskID,
                source: .timer,
                deviceID: "test",
                startedAt: startDate,
                endedAt: startDate.addingTimeInterval(600 + Double(index % 10) * 60)
            )
        }
        var store = RollupStore()
        let tasks = [parent] + children
        store.refresh(tasks: tasks, segments: segments, checklistItems: [], now: startDate.addingTimeInterval(7_200))

        let changedChild = try #require(children.first)
        let start = CFAbsoluteTimeGetCurrent()
        store.refreshAffected(
            taskIDs: [changedChild.id],
            tasks: tasks,
            segments: segments,
            checklistItems: [],
            now: startDate.addingTimeInterval(7_200)
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(store.rollup(for: parent.id)?.workedSeconds ?? 0 > 0)
        #expect(elapsed < 2.0)
    }

    @Test @MainActor
    func fiftyThousandSegmentMutationUsesConstantSizedRollupDelta() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 14,
            hour: 12
        )))
        let task = TaskNode(title: "Large History", parentID: nil, deviceID: "test")
        let historyStart = try #require(calendar.date(byAdding: .day, value: -60, to: now))
        let segments = (0..<50_000).map { index in
            let start = historyStart.addingTimeInterval(Double(index * 90))
            return TimeSegment(
                sessionID: UUID(),
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: start,
                endedAt: start.addingTimeInterval(60)
            )
        }
        let checklist = [
            ChecklistItem(taskID: task.id, title: "Done", isCompleted: true, sortOrder: 0, deviceID: "test"),
            ChecklistItem(taskID: task.id, title: "Next", isCompleted: false, sortOrder: 1, deviceID: "test")
        ]
        var incremental = RollupStore()
        incremental.refresh(
            tasks: [task],
            segments: segments,
            checklistItems: checklist,
            now: now,
            calendar: calendar
        )

        let original = try #require(segments.last)
        let updated = TimeSegment(
            sessionID: original.sessionID,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: original.startedAt,
            endedAt: try #require(original.endedAt).addingTimeInterval(120)
        )
        updated.id = original.id
        let start = CFAbsoluteTimeGetCurrent()
        incremental.refreshAffected(
            directTaskIDs: [task.id],
            explicitAncestorTaskIDs: [],
            segmentChanges: [
                LedgerSegmentChange(
                    id: original.id,
                    before: LedgerSegmentSnapshot(original),
                    after: LedgerSegmentSnapshot(updated)
                )
            ],
            checklistItemsByTaskID: [:],
            now: now,
            calendar: calendar
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        let facade = makeTestStore()
        facade.tasks = [task]
        facade.allSegments = segments
        facade.rollupDomainStore = incremental
        let rankingStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 {
            #expect(facade.frequentRecentTasks(limit: 1).first?.id == task.id)
        }
        let rankingElapsed = CFAbsoluteTimeGetCurrent() - rankingStart

        var rebuilt = RollupStore()
        rebuilt.refresh(
            tasks: [task],
            segments: Array(segments.dropLast()) + [updated],
            checklistItems: checklist,
            now: now,
            calendar: calendar
        )
        #expect(incremental.rollup(for: task.id) == rebuilt.rollup(for: task.id))
        #expect(elapsed < 0.25, "Incremental refresh took \(elapsed) seconds")
        #expect(rankingElapsed < 0.1, "Cached frequent-task ranking took \(rankingElapsed) seconds")
    }
}
