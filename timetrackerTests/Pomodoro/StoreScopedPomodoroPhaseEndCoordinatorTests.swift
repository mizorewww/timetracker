import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedPomodoroPhaseEndCoordinatorTests {
    @Test
    func oldFocusTokenCannotCompleteTheNextFocusRound() throws {
        let context = try makeTestContext()
        let task = try makeTask("ABA", context: context)
        let coordinator = makeCoordinator(context.container)
        let started = try coordinator.start(
            taskID: task.id,
            focusSeconds: 1500,
            breakSeconds: 300,
            longBreakSeconds: nil,
            targetRounds: 3
        )
        let firstFocus = started.startedFocus.phaseToken
        guard case .mutated = try coordinator.complete(phase: firstFocus) else {
            Issue.record("The current focus phase should complete")
            return
        }
        let firstBreak = try phaseToken(runID: firstFocus.runID, container: context.container)
        guard case let .resumed(resumed) = try coordinator.resume(
            phase: firstBreak
        ) else {
            Issue.record("The current break phase should resume")
            return
        }
        let secondFocus = resumed.resumedFocus.phaseToken
        #expect(secondFocus.stateRaw == firstFocus.stateRaw)
        #expect(secondFocus.mutationID != firstFocus.mutationID)

        #expect(try coordinator.complete(phase: firstFocus) == .rejected(.stalePhase))
        let run = try requiredRun(firstFocus.runID, container: context.container)
        #expect(run.state == .focusing)
        #expect(run.completedFocusRounds == 1)
        #expect(
            try timeRepository(context.container).activeSegments().map(\.id) ==
                [resumed.resumedFocus.segmentID]
        )
    }

    @Test
    func staleCancelCannotDowngradeACompletedRun() throws {
        let context = try makeTestContext()
        let task = try makeTask("Complete", context: context)
        let coordinator = makeCoordinator(context.container)
        let started = try coordinator.start(
            taskID: task.id,
            focusSeconds: 60,
            breakSeconds: 30,
            longBreakSeconds: nil,
            targetRounds: 1
        )
        let focus = started.startedFocus.phaseToken
        guard case .mutated = try coordinator.complete(phase: focus) else {
            Issue.record("The current focus phase should complete")
            return
        }
        let completed = try requiredRun(focus.runID, container: context.container)
        let completedMutationID = completed.clientMutationID
        let completedEnd = completed.endedAt

        #expect(try coordinator.cancel(phase: focus) == .rejected(.stalePhase))
        let repository = pomodoroRepository(ModelContext(context.container))
        try repository.cancel(runID: focus.runID)
        let preserved = try #require(try repository.run(id: focus.runID))
        #expect(preserved.state == .completed)
        #expect(preserved.clientMutationID == completedMutationID)
        #expect(preserved.endedAt == completedEnd)
        #expect(try timeRepository(context.container).activeSegments().isEmpty)
    }

    @Test
    func cancellingCurrentBreakPreservesFocusHistoryWithoutLedgerEvent() throws {
        let context = try makeTestContext()
        let task = try makeTask("Break", context: context)
        let coordinator = makeCoordinator(context.container)
        let started = try coordinator.start(
            taskID: task.id,
            focusSeconds: 600,
            breakSeconds: 60,
            longBreakSeconds: nil,
            targetRounds: 2
        )
        let focusSessionID = started.startedFocus.sessionID
        _ = try coordinator.complete(phase: started.startedFocus.phaseToken)
        let breakPhase = try phaseToken(
            runID: started.startedFocus.runID,
            container: context.container
        )

        guard case let .mutated(mutation) = try coordinator.cancel(phase: breakPhase) else {
            Issue.record("The current break phase should cancel")
            return
        }
        #expect(mutation.sessionIDBefore == nil)
        #expect(mutation.events == [
            .pomodoroChanged(runID: breakPhase.runID, sessionID: nil, taskID: task.id),
        ])
        let cancelled = try requiredRun(breakPhase.runID, container: context.container)
        #expect(cancelled.state == .cancelled)
        #expect(cancelled.completedFocusRounds == 1)
        #expect(
            try timeRepository(context.container).allSegments().contains {
                $0.sessionID == focusSessionID && $0.deletedAt == nil
            }
        )
    }

    @Test(arguments: [4 * 60, 6 * 60])
    func cancellationUsesFreshElapsedTimeForDiscardPolicy(elapsedSeconds: Int) throws {
        let context = try makeTestContext()
        let task = try makeTask("Threshold", context: context)
        let now = Date(timeIntervalSinceReferenceDate: 800_000)
        let coordinator = makeCoordinator(context.container, now: now)
        let started = try coordinator.start(
            taskID: task.id,
            focusSeconds: 25 * 60,
            breakSeconds: 5 * 60,
            longBreakSeconds: nil,
            targetRounds: 2
        )
        let siblingContext = ModelContext(context.container)
        let siblingRun = try #require(
            try pomodoroRepository(siblingContext).run(id: started.startedFocus.runID)
        )
        let siblingSegment = try #require(
            try SwiftDataTimeTrackingRepository(
                context: siblingContext,
                deviceID: "sibling"
            ).activeSegments().first { $0.id == started.startedFocus.segmentID }
        )
        siblingRun.startedAt = now.addingTimeInterval(-Double(elapsedSeconds))
        siblingSegment.startedAt = siblingRun.startedAt ?? now
        try siblingContext.save()

        guard case let .mutated(mutation) = try coordinator.cancel(
            phase: started.startedFocus.phaseToken
        ) else {
            Issue.record("The current focus phase should cancel")
            return
        }
        let shouldDiscard = elapsedSeconds < 5 * 60
        #expect(mutation.discardedRecord == shouldDiscard)
        let persistedRun = try pomodoroRepository(ModelContext(context.container))
            .run(id: started.startedFocus.runID)
        #expect((persistedRun == nil) == shouldDiscard)
        #expect(
            try timeRepository(context.container).allSegments().contains {
                $0.id == started.startedFocus.segmentID
            } == !shouldDiscard
        )
    }

    @Test
    func cancellingExpiredFinalFocusCompletesInsteadOfDowngrading() throws {
        let context = try makeTestContext()
        let task = try makeTask("Deadline", context: context)
        let startedAt = Date(timeIntervalSinceReferenceDate: 900_000)
        let started = try makeCoordinator(context.container, now: startedAt).start(
            taskID: task.id,
            focusSeconds: 60,
            breakSeconds: 30,
            longBreakSeconds: nil,
            targetRounds: 1
        )

        guard case let .mutated(mutation) = try makeCoordinator(
            context.container,
            now: startedAt.addingTimeInterval(120)
        ).cancel(phase: started.startedFocus.phaseToken) else {
            Issue.record("The expired current phase should settle")
            return
        }
        #expect(mutation.resultingStateRaw == PomodoroState.completed.rawValue)
        #expect(mutation.discardedRecord == false)
        let completed = try requiredRun(started.startedFocus.runID, container: context.container)
        #expect(completed.state == .completed)
        #expect(completed.endedAt == startedAt.addingTimeInterval(60))
        let segment = try #require(
            try timeRepository(context.container).allSegments().first {
                $0.id == started.startedFocus.segmentID
            }
        )
        #expect(segment.endedAt == startedAt.addingTimeInterval(60))
    }

    @Test(arguments: [false, true])
    func breakResumeReplacesSameTaskTimerAndHonorsParallelPreference(
        allowParallelTimers: Bool
    ) throws {
        let context = try makeTestContext()
        let task = try makeTask("Pomodoro", context: context)
        let otherTask = try makeTask("Other", context: context)
        let coordinator = makeCoordinator(context.container)
        let started = try coordinator.start(
            taskID: task.id,
            focusSeconds: 600,
            breakSeconds: 60,
            longBreakSeconds: nil,
            targetRounds: 2
        )
        _ = try coordinator.complete(phase: started.startedFocus.phaseToken)
        let breakPhase = try phaseToken(
            runID: started.startedFocus.runID,
            container: context.container
        )

        let mutationContext = ModelContext(context.container)
        let repository = SwiftDataTimeTrackingRepository(
            context: mutationContext,
            deviceID: "test"
        )
        let sameTaskSegment = try repository.startTask(
            taskID: task.id,
            source: .timer
        )
        let otherTaskSegment = try repository.startTask(
            taskID: otherTask.id,
            source: .timer
        )
        try PreferenceCommandHandler().set(
            key: .allowParallelTimers,
            valueJSON: PreferenceJSON.encode(allowParallelTimers),
            context: mutationContext
        )

        guard case let .resumed(resumed) = try coordinator.resume(phase: breakPhase) else {
            Issue.record("The current break phase should resume")
            return
        }

        let stoppedIDs = Set(resumed.stoppedSegments.map(\.segmentID))
        var expectedStoppedIDs: Set<UUID> = [sameTaskSegment.id]
        if !allowParallelTimers {
            expectedStoppedIDs.insert(otherTaskSegment.id)
        }
        #expect(stoppedIDs == expectedStoppedIDs)

        let activeIDs = try Set(
            timeRepository(context.container).activeSegments().map(\.id)
        )
        var expectedActiveIDs: Set<UUID> = [resumed.resumedFocus.segmentID]
        if allowParallelTimers {
            expectedActiveIDs.insert(otherTaskSegment.id)
        }
        #expect(activeIDs == expectedActiveIDs)
        #expect(activeIDs.contains(sameTaskSegment.id) == false)
    }

    private func makeCoordinator(
        _ container: ModelContainer,
        now: Date = Date()
    ) -> StoreScopedPomodoroCommandCoordinator {
        StoreScopedPomodoroCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "test",
            nowProvider: { now }
        )
    }

    private func makeTask(_ title: String, context: ModelContext) throws -> TaskNode {
        try SwiftDataTaskRepository(context: context, deviceID: "test").createTask(
            title: title,
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
    }

    private func phaseToken(
        runID: UUID,
        container: ModelContainer
    ) throws -> PomodoroPhaseToken {
        try PomodoroPhaseToken(run: requiredRun(runID, container: container))
    }

    private func requiredRun(
        _ runID: UUID,
        container: ModelContainer
    ) throws -> PomodoroRun {
        try #require(try pomodoroRepository(ModelContext(container)).run(id: runID))
    }

    private func timeRepository(
        _ container: ModelContainer
    ) -> SwiftDataTimeTrackingRepository {
        SwiftDataTimeTrackingRepository(
            context: ModelContext(container),
            deviceID: "test"
        )
    }

    private func pomodoroRepository(
        _ context: ModelContext
    ) -> SwiftDataPomodoroRepository {
        SwiftDataPomodoroRepository(
            context: context,
            timeRepository: SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: "test"
            ),
            deviceID: "test"
        )
    }
}
