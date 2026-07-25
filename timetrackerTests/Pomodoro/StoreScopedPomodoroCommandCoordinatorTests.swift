import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedPomodoroCommandCoordinatorTests {
    @Test
    func exclusiveStartDiscoversAndStopsSiblingTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let focusTask = try makeTask("Focus", repository: taskRepository)
        let otherTask = try makeTask("Other", repository: taskRepository)
        let siblingSegment = try SwiftDataTimeTrackingRepository(
            context: ModelContext(context.container),
            deviceID: "sibling"
        ).startTask(taskID: otherTask.id, source: .timer)
        try setTestAllowParallelTimers(false, context: context)

        let outcome = try coordinator(context.container).start(
            taskID: focusTask.id,
            focusSeconds: 1500,
            breakSeconds: 300,
            longBreakSeconds: nil,
            targetRounds: 2
        )

        #expect(outcome.stoppedSegments.map(\.segmentID) == [siblingSegment.id])
        let freshContext = ModelContext(context.container)
        let activeSegments = try SwiftDataTimeTrackingRepository(
            context: freshContext,
            deviceID: "test"
        ).activeSegments()
        #expect(activeSegments.count == 1)
        #expect(activeSegments.first?.taskID == focusTask.id)
        #expect(activeSegments.first?.source == .pomodoro)
        #expect(
            try SwiftDataPomodoroRepository(
                context: freshContext,
                timeRepository: SwiftDataTimeTrackingRepository(
                    context: freshContext,
                    deviceID: "test"
                ),
                deviceID: "test"
            ).activeRuns().map(\.id) == [outcome.startedFocus.runID]
        )
    }

    @Test
    func archivedTaskStartDoesNotStopUnrelatedTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let focusTask = try makeTask("Unavailable", repository: taskRepository)
        let otherTask = try makeTask("Other", repository: taskRepository)
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let otherSegment = try timeRepository.startTask(taskID: otherTask.id, source: .timer)
        try taskRepository.archiveTask(taskID: focusTask.id)

        #expect(throws: SystemActionCommandError.taskNotFound) {
            _ = try coordinator(context.container).start(
                taskID: focusTask.id,
                focusSeconds: 1500,
                breakSeconds: 300,
                longBreakSeconds: nil,
                targetRounds: 2
            )
        }

        #expect(try timeRepository.activeSegments().map(\.id) == [otherSegment.id])
        #expect(try pomodoroRepository(context).activeRuns().isEmpty)
    }

    @Test
    func healthSyncTaskStartDoesNotStopUnrelatedTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        )
        let otherTask = try makeTask("Other", repository: taskRepository)
        let healthTask = TaskNode(
            title: "Imported sleep",
            parentID: nil,
            deviceID: "health"
        )
        healthTask.id = AppleHealthTaskCatalog.taskDefinition(for: .sleep).id
        context.insert(healthTask)
        try context.save()
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test"
        )
        let otherSegment = try timeRepository.startTask(
            taskID: otherTask.id,
            source: .timer
        )

        #expect(throws: SystemActionCommandError.taskNotFound) {
            _ = try coordinator(context.container).start(
                taskID: healthTask.id,
                focusSeconds: 1500,
                breakSeconds: 300,
                longBreakSeconds: nil,
                targetRounds: 2
            )
        }

        #expect(try timeRepository.activeSegments().map(\.id) == [otherSegment.id])
        #expect(try pomodoroRepository(context).activeRuns().isEmpty)
    }

    @Test
    func legacyCompletedTaskStartRemainsUsable() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let focusTask = try makeTask("Legacy completed", repository: taskRepository)
        let otherTask = try makeTask("Other", repository: taskRepository)
        focusTask.statusRaw = LegacyTaskStatusRaw.completed
        try context.save()
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let otherSegment = try timeRepository.startTask(taskID: otherTask.id, source: .timer)
        try setTestAllowParallelTimers(false, context: context)

        let outcome = try coordinator(context.container).start(
            taskID: focusTask.id,
            focusSeconds: 1500,
            breakSeconds: 300,
            longBreakSeconds: nil,
            targetRounds: 2
        )

        #expect(outcome.stoppedSegments.map(\.segmentID) == [otherSegment.id])
        let freshContext = ModelContext(context.container)
        let activeSegments = try SwiftDataTimeTrackingRepository(
            context: freshContext,
            deviceID: "test"
        ).activeSegments()
        #expect(activeSegments.count == 1)
        #expect(activeSegments.first?.taskID == focusTask.id)
        #expect(activeSegments.first?.source == .pomodoro)
        #expect(
            try pomodoroRepository(freshContext).activeRuns().map(\.id) ==
                [outcome.startedFocus.runID]
        )
    }

    @Test
    func sameBreakPhaseCanResumeOnlyOnce() throws {
        let context = try makeTestContext()
        let task = try makeTask(
            "Double resume",
            repository: SwiftDataTaskRepository(context: context, deviceID: "test")
        )
        let started = try coordinator(context.container).start(
            taskID: task.id,
            focusSeconds: 1500,
            breakSeconds: 300,
            longBreakSeconds: nil,
            targetRounds: 3
        )
        let phase = try completeFocusAndBreakToken(
            runID: started.startedFocus.runID,
            container: context.container
        )

        let first = try coordinator(context.container).resume(
            phase: phase
        )
        guard case .resumed = first else {
            Issue.record("The current break phase should resume")
            return
        }
        #expect(
            try coordinator(context.container).resume(
                phase: phase
            ) == .rejected(.stalePhase)
        )
        #expect(try timeRepository(context.container).activeSegments().count == 1)
    }

    @Test
    func firstRoundTokenCannotResumeSecondRoundBreak() throws {
        let context = try makeTestContext()
        let task = try makeTask(
            "ABA",
            repository: SwiftDataTaskRepository(context: context, deviceID: "test")
        )
        let started = try coordinator(context.container).start(
            taskID: task.id,
            focusSeconds: 1500,
            breakSeconds: 300,
            longBreakSeconds: nil,
            targetRounds: 3
        )
        let firstBreak = try completeFocusAndBreakToken(
            runID: started.startedFocus.runID,
            container: context.container
        )
        _ = try coordinator(context.container).resume(
            phase: firstBreak
        )
        let secondBreak = try completeFocusAndBreakToken(
            runID: started.startedFocus.runID,
            container: context.container
        )
        #expect(secondBreak.stateRaw == firstBreak.stateRaw)
        #expect(secondBreak.mutationID != firstBreak.mutationID)

        #expect(
            try coordinator(context.container).resume(
                phase: firstBreak
            ) == .rejected(.stalePhase)
        )
        #expect(try timeRepository(context.container).activeSegments().isEmpty)
    }

    @Test
    func exclusiveResumeDiscoversAndStopsSiblingTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let focusTask = try makeTask("Focus", repository: taskRepository)
        let otherTask = try makeTask("Other", repository: taskRepository)
        let started = try coordinator(context.container).start(
            taskID: focusTask.id,
            focusSeconds: 1500,
            breakSeconds: 300,
            longBreakSeconds: nil,
            targetRounds: 2
        )
        let phase = try completeFocusAndBreakToken(
            runID: started.startedFocus.runID,
            container: context.container
        )
        let siblingSegment = try timeRepository(context.container)
            .startTask(taskID: otherTask.id, source: .timer)
        try setTestAllowParallelTimers(false, context: context)

        let outcome = try coordinator(context.container).resume(
            phase: phase
        )
        guard case let .resumed(mutation) = outcome else {
            Issue.record("The current break phase should resume")
            return
        }
        #expect(mutation.stoppedSegments.map(\.segmentID) == [siblingSegment.id])
        let activeSegments = try timeRepository(context.container).activeSegments()
        #expect(activeSegments.count == 1)
        #expect(activeSegments.first?.taskID == focusTask.id)
        #expect(activeSegments.first?.source == .pomodoro)
    }

    @Test
    func archivedTaskResumeDoesNotStopUnrelatedTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let focusTask = try makeTask("Focus", repository: taskRepository)
        let otherTask = try makeTask("Other", repository: taskRepository)
        let started = try coordinator(context.container).start(
            taskID: focusTask.id,
            focusSeconds: 1500,
            breakSeconds: 300,
            longBreakSeconds: nil,
            targetRounds: 2
        )
        let phase = try completeFocusAndBreakToken(
            runID: started.startedFocus.runID,
            container: context.container
        )
        let otherSegment = try timeRepository(context.container)
            .startTask(taskID: otherTask.id, source: .timer)
        try taskRepository.archiveTask(taskID: focusTask.id)

        #expect(
            try coordinator(context.container).resume(
                phase: phase
            ) == .rejected(.taskUnavailable(focusTask.id))
        )
        #expect(try timeRepository(context.container).activeSegments().map(\.id) == [otherSegment.id])
        let run = try #require(try pomodoroRepository(context).run(id: phase.runID))
        #expect(run.state == .shortBreak)
        #expect(run.sessionID == nil)
    }

    private func coordinator(
        _ container: ModelContainer
    ) -> StoreScopedPomodoroCommandCoordinator {
        StoreScopedPomodoroCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "test"
        )
    }

    private func makeTask(
        _ title: String,
        repository: SwiftDataTaskRepository
    ) throws -> TaskNode {
        try repository.createTask(
            title: title,
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
    }

    private func completeFocusAndBreakToken(
        runID: UUID,
        container: ModelContainer
    ) throws -> PomodoroPhaseToken {
        let context = ModelContext(container)
        let repository = pomodoroRepository(context)
        #expect(
            try repository.completeFocus(
                runID: runID,
                expectedState: .focusing,
                endedAt: Date()
            )
        )
        let run = try #require(try repository.run(id: runID))
        #expect(run.state == .shortBreak || run.state == .longBreak)
        return PomodoroPhaseToken(run: run)
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
