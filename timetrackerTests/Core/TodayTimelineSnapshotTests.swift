import Foundation
import SwiftData
import Testing
@testable import timetracker

/// Today read-model cache contracts for the timeline.
///
/// The cache is an internal accelerator, so these tests assert the observable
/// snapshot semantics the cache must preserve: repeated same-minute reads are
/// identical, every durable change (ledger write, task edit, minute advance on
/// a live segment) is reflected on the next read. A stale cache fails here.
@Suite(.serialized)
@MainActor
struct TodayTimelineSnapshotTests {
    private func makeStoreWithSegments(
        now: Date
    ) throws -> (TimeTrackerStore, TaskNode, TimeSegment) {
        let context = try makeTestContext()
        let store = makeTestStore()
        try store.configureIfNeeded(context: context)
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "seed"
        ).createTask(
            title: "Timeline owner",
            parentID: nil,
            colorHex: "1677FF",
            iconName: "chart.bar"
        )
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "seed"
        )
        // Anchor to the start of the local day: offsets from `now` can cross
        // midnight into the previous day, and the Today timeline only shows
        // the current day's segments. Keep the end strictly before `now` and
        // never before day start + 2 min (right after midnight the segment
        // simply becomes short).
        let dayStart = Calendar.current.startOfDay(for: now)
        let endedAt = max(
            dayStart.addingTimeInterval(120),
            min(now.addingTimeInterval(-60), dayStart.addingTimeInterval(7200))
        )
        let segment = try repository.addManualSegment(
            taskID: task.id,
            startedAt: dayStart.addingTimeInterval(60),
            endedAt: endedAt,
            note: nil
        )
        try store.refreshLedgerDomain(
            plan: StoreRefreshPlan(scopes: [.ledgerVisible, .ledgerHistory])
        )
        return (store, task, segment)
    }

    @Test
    func ledgerMutationIsReflectedAfterCachedRead() throws {
        let (store, task, _) = try makeStoreWithSegments(now: Date())
        let beforeNow = Date()
        let before = store.todaySnapshot(now: beforeNow).live.timeline
        #expect(before.entries.count == 1)

        // Durable ledger write through the facade path (starts a second timer).
        #expect(try store.startTask(task))
        let afterNow = Date()
        let after = store.todaySnapshot(now: afterNow).live.timeline

        #expect(after.entries.count == 2)
        let activeEntry = try #require(
            after.entries.first { $0.usesCurrentEndLabel }
        )
        #expect(activeEntry.taskID == task.id)
    }

    @Test
    func taskEditIsReflectedAfterCachedRead() throws {
        let now = Date()
        let (store, task, _) = try makeStoreWithSegments(now: now)
        let before = store.todaySnapshot(now: now).live.timeline
        #expect(before.entries.first?.title == "Timeline owner")

        var draft = TaskEditorDraft(
            task: task,
            checklistItems: []
        )
        draft.title = "Renamed owner"
        draft.colorHex = "7C3AED"
        draft.iconName = "checklist"
        let result = store.saveTaskDraftResult(draft)
        guard case .saved = result else {
            Issue.record("Task draft save failed: \(result)")
            return
        }

        let after = store.todaySnapshot(now: now).live.timeline
        #expect(after.entries.first?.title == "Renamed owner")
        #expect(after.entries.first?.colorHex == "7C3AED")
    }

    @Test
    func minuteAdvanceRefreshesLiveActiveSegment() throws {
        let now = Date()
        let (store, task, _) = try makeStoreWithSegments(now: now)
        #expect(try store.startTask(task))

        let firstNow = now.addingTimeInterval(60)
        let first = store.todaySnapshot(now: firstNow).live.timeline
        let later = now.addingTimeInterval(180)
        let second = store.todaySnapshot(now: later).live.timeline

        let firstEntry = try #require(
            first.entries.first { $0.taskID == task.id && $0.usesCurrentEndLabel }
        )
        let secondEntry = try #require(
            second.entries.first { $0.taskID == task.id && $0.usesCurrentEndLabel }
        )
        #expect(secondEntry.durationSeconds > firstEntry.durationSeconds)
        #expect(secondEntry.endedAt > firstEntry.endedAt)
    }

    @Test
    func startedTimerRefreshesCachedContentAndMarksTodayLive() throws {
        let now = Date()
        let (store, task, _) = try makeStoreWithSegments(now: now)
        let before = store.todaySnapshot(now: now)
        #expect(before.content.activeSegments.isEmpty)
        #expect(before.live.isLive == false)

        #expect(try store.startTask(task))
        let later = Date()
        let after = store.todaySnapshot(now: later)

        #expect(after.content.activeSegments.map(\.taskID) == [task.id])
        #expect(after.live.isLive)
        #expect(after.live.rows.first?.usesCurrentEndLabel == true)
        #expect(after.live.metrics.grossSeconds >= before.live.metrics.grossSeconds)
    }
}
