import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedTimerCommandCoordinatorTests {
    @Test
    func staleCallersStartingTheSameTaskConvergeOnOneSegment() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "One logical timer",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let firstCaller = ModelContext(container)
        let secondCaller = ModelContext(container)
        let handler = makeTestSystemActionCommandHandler()

        let first = try handler.startTimerMutation(
            taskID: task.id,
            allowParallelTimers: true,
            container: firstCaller.container
        )
        let second = try handler.startTimerMutation(
            taskID: task.id,
            allowParallelTimers: true,
            container: secondCaller.container
        )

        #expect(first.subjectSegmentID != nil)
        #expect(second.subjectSegmentID == first.subjectSegmentID)
        #expect(first.createdSegment?.segmentID == first.subjectSegmentID)
        #expect(second.didMutate == false)
        let active = try freshTimeRepository(container).activeSegments()
        #expect(active.map(\.id) == [first.subjectSegmentID])
    }

    @Test
    func repeatedSameTaskRowsKeepTheOldestAndCloseDuplicates() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Duplicate timer",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        )
        let older = try repository.startTask(taskID: task.id, source: .timer)
        let newer = try repository.startTask(taskID: task.id, source: .watch)
        older.startedAt = Date(timeIntervalSinceReferenceDate: 100)
        newer.startedAt = Date(timeIntervalSinceReferenceDate: 200)
        try context.save()

        let outcome = try makeTestSystemActionCommandHandler().startTimerMutation(
            taskID: task.id,
            allowParallelTimers: true,
            container: container
        )

        #expect(outcome.subjectSegmentID == older.id)
        #expect(outcome.createdSegment == nil)
        #expect(outcome.stoppedSegments.map(\.segmentID) == [newer.id])
        let freshRepository = freshTimeRepository(container)
        #expect(try freshRepository.activeSegments().map(\.id) == [older.id])
        #expect(
            try freshRepository.allSegments().first { $0.id == newer.id }?.endedAt
                != nil
        )
    }

    @Test
    func exclusiveStartStopsEveryOtherTaskInsideTheTransaction() throws {
        let context = try makeTestContext()
        let container = context.container
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let selectedTask = try taskRepository.createTask(
            title: "Selected",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let otherTask = try taskRepository.createTask(
            title: "Other",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        )
        let selected = try repository.startTask(
            taskID: selectedTask.id,
            source: .timer
        )
        let other = try repository.startTask(taskID: otherTask.id, source: .watch)

        let outcome = try makeTestSystemActionCommandHandler().startTimerMutation(
            taskID: selectedTask.id,
            allowParallelTimers: false,
            container: container
        )

        #expect(outcome.subjectSegmentID == selected.id)
        #expect(outcome.stoppedSegments.map(\.segmentID) == [other.id])
        #expect(
            try freshTimeRepository(container).activeSegments().map(\.id)
                == [selected.id]
        )
    }

    @Test
    func staleExactStopNeverFallsBackToAnotherActiveSegment() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Still running",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let running = try SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        ).startTask(taskID: task.id, source: .timer)

        let outcome = try makeTestSystemActionCommandHandler().stopTimerMutation(
            segmentID: UUID(),
            container: container
        )

        #expect(outcome.subjectSegmentID == nil)
        #expect(outcome.didMutate == false)
        #expect(
            try freshTimeRepository(container).activeSegments().map(\.id)
                == [running.id]
        )
    }

    @Test
    func staleStopAfterReplacementCannotCloseTheReplacement() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Replace safely",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let oldSegment = try SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        ).startTask(taskID: task.id, source: .timer)
        let coordinator = StoreScopedTimerCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "test"
        )

        let replacement = try coordinator.start(
            taskID: task.id,
            allowParallelTimers: true,
            sameTaskBehavior: .replaceAll
        )
        let staleStop = try coordinator.stop(segmentID: oldSegment.id)

        let replacementID = try #require(replacement.subjectSegmentID)
        #expect(replacementID != oldSegment.id)
        #expect(staleStop.subjectSegmentID == nil)
        #expect(
            try freshTimeRepository(container).activeSegments().map(\.id)
                == [replacementID]
        )
    }

    private func freshTimeRepository(
        _ container: ModelContainer
    ) -> SwiftDataTimeTrackingRepository {
        SwiftDataTimeTrackingRepository(
            context: ModelContext(container),
            deviceID: "test"
        )
    }
}
