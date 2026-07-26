import Foundation
import Observation
import SwiftData
import Testing
@testable import timetracker

/// The timeline chart clips an active interval to `now`, while the matching row
/// also needs to preserve the value-semantic fact that the end label is "Now".
/// A stopped timer must update both facts in one shared snapshot.
///
/// These read through the store's own read models rather than through a fresh
/// `ModelContext`, because the fresh-context read is what the existing timer
/// tests do and it is precisely what hides this defect: the stop is committed
/// on a sibling context, so only a reader that shares the app's main context
/// can observe the staleness.
@Suite(.serialized)
struct TodayTimelineStopTests {
    @Test @MainActor
    func stoppingATimerEndsItsTimelineBarInsteadOfGrowingToNow() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Running task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let startedAt = Date().addingTimeInterval(-30 * 60)
        let segment = try timeRepository.startTask(taskID: task.id, source: .timer)
        segment.startedAt = startedAt
        try context.save()

        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)

        let runningNow = Date()
        let runningTimeline = store.timelineSnapshot(
            segments: store.timelineSegments,
            date: runningNow,
            now: runningNow
        )
        let runningEntry = try #require(
            runningTimeline.entries.first { $0.taskID == task.id }
        )
        #expect(runningEntry.usesCurrentEndLabel)

        store.stop(segment: segment)

        let stopObservedAt = Date()
        // Look well past the stop, the way the chart's 60-second TimelineView
        // does. A bar that is still open would stretch to this value.
        let laterNow = stopObservedAt.addingTimeInterval(10 * 60)
        let timeline = store.timelineSnapshot(
            segments: store.timelineSegments,
            date: stopObservedAt,
            now: laterNow
        )
        let entry = try #require(
            timeline.entries.first { $0.taskID == task.id },
            "The stopped segment disappeared from the Today timeline entirely."
        )

        #expect(
            entry.endedAt <= stopObservedAt.addingTimeInterval(1),
            """
            The timeline bar for a stopped timer still runs to \(entry.endedAt), \
            past the stop at ~\(stopObservedAt). It is being rendered as if the \
            timer were still active.
            """
        )
        #expect(entry.endedAt < laterNow)
        #expect(entry.usesCurrentEndLabel == false)
    }

    /// The store's own visible read model must report the segment as closed.
    /// If this fails, the staleness is in the ledger refresh rather than in the
    /// timeline projection.
    @Test @MainActor
    func stoppingATimerClosesItInTheStoreVisibleReadModel() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Running task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let segment = try timeRepository.startTask(taskID: task.id, source: .timer)
        try context.save()

        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)

        store.stop(segment: segment)

        #expect(store.activeSegments.isEmpty, "Now section still shows a running timer.")

        let visible = try #require(
            store.timelineSegments.first { $0.id == segment.id },
            "The stopped segment left the visible ledger read model."
        )
        #expect(
            visible.endedAt != nil,
            "The store's visible segment still reports endedAt == nil after a stop."
        )
    }

    /// SwiftData may merge a sibling-context edit into the same `@Model`
    /// instance. The segment array then remains identity-equal even though its
    /// persisted fields changed, so the Today projection needs a value-semantic
    /// invalidation dependency of its own.
    @Test @MainActor
    func stoppingATimerInvalidatesTheObservedTimelineProjection() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Observed task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let segment = try timeRepository.startTask(taskID: task.id, source: .timer)
        segment.startedAt = Date().addingTimeInterval(-30 * 60)
        try context.save()

        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)

        var didInvalidate = false
        withObservationTracking {
            let now = Date()
            _ = store.timelineSnapshot(
                segments: store.timelineSegments,
                date: now,
                now: now
            )
        } onChange: {
            didInvalidate = true
        }

        store.stop(segment: segment)

        #expect(
            didInvalidate,
            """
            Stopping the timer changed the timeline projection but did not \
            invalidate its Observation dependency, so SwiftUI can keep the \
            pre-stop chart mounted.
            """
        )
    }
}
