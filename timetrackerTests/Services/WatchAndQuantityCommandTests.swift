import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct WatchAndQuantityCommandTests {
    @Test
    func repeatedWatchStartKeepsOneRunningSegment() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "seed")
            .createTask(title: "Walk", parentID: nil)
        let processor = WatchCommandProcessor(writeAuthorization: .isolatedTestHarness)
        let now = Date()

        let first = try processor.processWithMutationOutcome(
            command(.startTask, taskID: task.id, issuedAt: now), context: context, now: now
        )
        let retry = try processor.processWithMutationOutcome(
            command(.startTask, taskID: task.id, issuedAt: now), context: context, now: now
        )

        guard case let .started(segmentID) = first.result else {
            Issue.record("Expected a started result, got \(first.result)")
            return
        }
        #expect(retry.result == .started(segmentID))
        let active = try SwiftDataTimeTrackingRepository(context: ModelContext(context.container))
            .activeSegments()
        #expect(active.map(\.id) == [segmentID])
    }

    @Test
    func watchStopClosesTheSegmentAndARepeatChangesNothing() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "seed")
            .createTask(title: "Read", parentID: nil)
        let processor = WatchCommandProcessor(writeAuthorization: .isolatedTestHarness)
        let now = Date()
        let started = try processor.processWithMutationOutcome(
            command(.startTask, taskID: task.id, issuedAt: now), context: context, now: now
        )
        guard case let .started(segmentID) = started.result else {
            Issue.record("Expected a started result, got \(started.result)")
            return
        }

        let stop = command(.stopSegment, segmentID: segmentID, issuedAt: now)
        let stopped = try processor.processWithMutationOutcome(stop, context: context, now: now)
        let repeated = try processor.processWithMutationOutcome(stop, context: context, now: now)

        #expect(stopped.result == .stopped(segmentID))
        #expect(repeated.events.isEmpty)
        #expect(try SwiftDataTimeTrackingRepository(context: ModelContext(context.container))
            .activeSegments().isEmpty)
    }

    @Test
    func staleOrUnknownWatchCommandsDoNotWrite() throws {
        let context = try makeTestContext()
        let processor = WatchCommandProcessor(writeAuthorization: .isolatedTestHarness)
        let now = Date()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "seed")
            .createTask(title: "Old tap", parentID: nil)
        let missingTaskID = UUID()

        let stale = try processor.processWithMutationOutcome(
            command(
                .startTask,
                taskID: task.id,
                issuedAt: now.addingTimeInterval(-WatchTransportLimits.maximumCommandAge - 1)
            ),
            context: context,
            now: now
        )
        let missing = try processor.processWithMutationOutcome(
            command(.startTask, taskID: missingTaskID, issuedAt: now), context: context, now: now
        )

        #expect(stale.result == .invalid)
        #expect(missing.result == .missingTask(missingTaskID))
        #expect(try ModelContext(context.container).fetch(FetchDescriptor<TimeSegment>()).isEmpty)
    }

    @Test
    func quantityEntriesRejectInvalidAmountsAndReplayByEntryID() throws {
        let context = try makeTestContext()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let task = try SwiftDataTaskRepository(context: context, deviceID: "seed")
            .createTask(title: "Water", parentID: nil)
        var draft = TaskEditorDraft(task: task, checklistItems: [])
        draft.quantityGoal = TaskQuantityGoalDraft(targetAmount: 8, unitLabel: "cups")
        guard case let .saved(taskID) = store.saveTaskDraftResult(draft) else {
            Issue.record("Goal save failed")
            return
        }
        let entryID = UUID()

        #expect(store.recordTaskQuantity(taskID: taskID, amount: 0, entryID: UUID()) == false)
        #expect(store.recordTaskQuantity(taskID: taskID, amount: 2, entryID: entryID))
        _ = store.recordTaskQuantity(taskID: taskID, amount: 2, entryID: entryID)

        let entries = try ModelContext(context.container)
            .fetch(FetchDescriptor<TaskQuantityEntry>())
            .filter { $0.deletedAt == nil }
        #expect(entries.map(\.amount) == [2])
    }

    private func command(
        _ type: WatchTimerCommandType,
        taskID: UUID? = nil,
        segmentID: UUID? = nil,
        issuedAt: Date
    ) -> WatchTimerCommand {
        WatchTimerCommand(
            id: UUID(),
            type: type,
            taskID: taskID,
            segmentID: segmentID,
            issuedAt: issuedAt,
            deviceID: "watch-test"
        )
    }
}
