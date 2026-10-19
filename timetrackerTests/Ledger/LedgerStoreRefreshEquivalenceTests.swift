import Foundation
import SwiftData
import Testing
@testable import timetracker

/// Scoped ledger refreshes (history ranges + visible window) must leave the
/// in-memory ledger and the incrementally updated rollups exactly where a
/// full rebuild from SwiftData would put them.
@Suite(.serialized)
@MainActor
struct LedgerStoreRefreshEquivalenceTests {
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86400

    @Test
    func scopedRefreshesMatchAFullRebuild() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTimeTrackingRepository(context: context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)))
        let today = try #require(calendar.dateInterval(of: .day, for: now))

        let taskA = TaskNode(title: "A", parentID: nil, deviceID: "test")
        let taskB = TaskNode(title: "B", parentID: nil, deviceID: "test")
        context.insert(taskA)
        context.insert(taskB)
        func insert(_ task: TaskNode, _ start: TimeInterval, _ end: TimeInterval?) -> TimeSegment {
            let session = TimeSession(
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: now.addingTimeInterval(start)
            )
            let segment = TimeSegment(
                sessionID: session.id,
                taskID: task.id,
                source: .timer,
                deviceID: "test",
                startedAt: now.addingTimeInterval(start),
                endedAt: end.map { now.addingTimeInterval($0) }
            )
            context.insert(session)
            context.insert(segment)
            return segment
        }

        let moved = insert(taskA, -3 * day, -3 * day + hour)
        _ = insert(taskA, -2 * hour, -hour)
        _ = insert(taskB, -0.5 * hour, nil)
        _ = insert(taskB, -400 * day, -10 * day)
        _ = insert(taskA, -hour, 2 * hour)
        let deleted = insert(taskB, -40 * day, -40 * day + 2 * hour)
        let closedYesterday = insert(taskB, -20 * hour, nil)
        try context.save()

        var incremental = LedgerStore()
        try incremental.refresh(repository: repository, now: now, calendar: calendar)
        var incrementalRollups = RollupStore()
        try incrementalRollups.refresh(
            tasks: [taskA, taskB],
            segments: repository.allSegments(),
            checklistItems: [],
            now: now,
            calendar: calendar
        )

        let movedRange = StoreInvalidationRange(start: moved.startedAt, end: moved.endedAt ?? now)
        moved.startedAt = now.addingTimeInterval(-5 * day)
        moved.endedAt = now.addingTimeInterval(-5 * day + hour)
        deleted.deletedAt = now
        closedYesterday.endedAt = now.addingTimeInterval(-14 * hour)
        let inserted = insert(taskA, -7 * day, -7 * day + 0.5 * hour)
        try context.save()

        let later = now.addingTimeInterval(60)
        incremental.resetRollupChanges()
        try incremental.refreshHistoryRanges(
            repository: repository,
            ranges: [
                movedRange,
                StoreInvalidationRange(start: moved.startedAt, end: moved.endedAt ?? later),
                StoreInvalidationRange(start: deleted.startedAt, end: deleted.endedAt ?? later),
                StoreInvalidationRange(start: inserted.startedAt, end: inserted.endedAt ?? later),
            ],
            now: later
        )
        try incremental.refreshVisible(repository: repository, now: later, calendar: calendar)
        incrementalRollups.refreshAffected(
            directTaskIDs: [],
            explicitAncestorTaskIDs: [],
            segmentChanges: incremental.rollupChanges,
            checklistItemsByTaskID: [:],
            now: later,
            calendar: calendar
        )

        var rebuilt = LedgerStore()
        try rebuilt.refresh(repository: repository, now: later, calendar: calendar)
        var rebuiltRollups = RollupStore()
        try rebuiltRollups.refresh(
            tasks: [taskA, taskB],
            segments: repository.allSegments(),
            checklistItems: [],
            now: later,
            calendar: calendar
        )

        let intervals = [
            DateInterval(start: today.start, end: today.end),
            DateInterval(start: today.start.addingTimeInterval(-7 * day), end: today.end),
            DateInterval(start: today.start.addingTimeInterval(-30 * day), end: today.end),
            DateInterval(start: today.start.addingTimeInterval(-500 * day), end: today.end),
            DateInterval(start: today.start.addingTimeInterval(-5 * day), duration: day),
            DateInterval(start: today.start.addingTimeInterval(-3 * day), duration: day),
        ]
        for interval in intervals {
            #expect(ids(incremental.segments(overlapping: interval, now: later)) ==
                ids(rebuilt.segments(overlapping: interval, now: later)))
            for taskID in [taskA.id, taskB.id] {
                #expect(ids(incremental.segments(
                    overlapping: interval,
                    taskIDs: [taskID],
                    evaluatedAt: later,
                    clockReference: later
                )) == ids(rebuilt.segments(
                    overlapping: interval,
                    taskIDs: [taskID],
                    evaluatedAt: later,
                    clockReference: later
                )))
            }
        }
        let history = ids(rebuilt.segments(overlapping: intervals[3], now: later))
        #expect(history.contains(inserted.id))
        #expect(history.contains(deleted.id) == false)
        #expect(incremental.segment(for: closedYesterday.id)?.endedAt == closedYesterday.endedAt)
        #expect(incremental.activeSegments.map(\.id) == rebuilt.activeSegments.map(\.id))
        #expect(incremental.todaySegments.map(\.id) == rebuilt.todaySegments.map(\.id))
        #expect(Set(incremental.sessions.map(\.id)) == Set(rebuilt.sessions.map(\.id)))
        #expect(incrementalRollups.taskRollups == rebuiltRollups.taskRollups)
    }

    private func ids(_ segments: [TimeSegment]) -> Set<UUID> {
        Set(segments.map(\.id))
    }
}
