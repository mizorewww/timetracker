import Foundation
import Testing
@testable import timetracker

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
}
