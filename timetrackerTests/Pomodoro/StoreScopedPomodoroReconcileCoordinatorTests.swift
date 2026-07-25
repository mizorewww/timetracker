import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedPomodoroReconcileCoordinatorTests {
    @Test
    func reconciliationDiscoversEveryCanonicalExpiredFocusAndLeavesBreakWaiting() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        var fixtures: [(run: PomodoroRun, segment: TimeSegment, deadline: Date)] = []

        for index in 0 ..< 2 {
            let task = try taskRepository.createTask(
                title: "Expired \(index)",
                parentID: nil,
                colorHex: nil,
                iconName: nil
            )
            let startedAt = now.addingTimeInterval(-Double(180 - index * 30))
            let session = TimeSession(
                taskID: task.id,
                source: .pomodoro,
                deviceID: "remote",
                startedAt: startedAt,
                titleSnapshot: task.title
            )
            let segment = TimeSegment(
                sessionID: session.id,
                taskID: task.id,
                source: .pomodoro,
                deviceID: "remote",
                startedAt: startedAt
            )
            let run = PomodoroRun(
                taskID: task.id,
                focus: 60,
                breakSeconds: 30,
                targetRounds: 2,
                deviceID: "remote"
            )
            run.sessionID = session.id
            run.startedAt = startedAt
            run.state = .focusing
            context.insert(session)
            context.insert(segment)
            context.insert(run)
            fixtures.append((run, segment, startedAt.addingTimeInterval(60)))
        }

        let breakTask = try taskRepository.createTask(
            title: "Waiting break",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let breakRun = PomodoroRun(
            taskID: breakTask.id,
            focus: 60,
            breakSeconds: 30,
            targetRounds: 2,
            deviceID: "remote"
        )
        breakRun.state = .shortBreak
        breakRun.startedAt = now.addingTimeInterval(-300)
        let breakMutationID = breakRun.clientMutationID
        context.insert(breakRun)
        try context.save()

        let outcome = try StoreScopedPomodoroCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "test",
            nowProvider: { now }
        ).reconcileExpiredFocuses(observedAt: now)

        #expect(outcome.mutations.count == 2)
        #expect(outcome.events.count == 4)
        let freshContext = ModelContext(context.container)
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: freshContext,
            deviceID: "test"
        )
        let pomodoroRepository = SwiftDataPomodoroRepository(
            context: freshContext,
            timeRepository: timeRepository,
            deviceID: "test"
        )
        for fixture in fixtures {
            let run = try #require(try pomodoroRepository.run(id: fixture.run.id))
            let segment = try #require(
                try timeRepository.allSegments().first { $0.id == fixture.segment.id }
            )
            #expect(run.state == .shortBreak)
            #expect(run.sessionID == nil)
            #expect(segment.endedAt == fixture.deadline)
        }
        let preservedBreak = try #require(try pomodoroRepository.run(id: breakRun.id))
        #expect(preservedBreak.state == .shortBreak)
        #expect(preservedBreak.clientMutationID == breakMutationID)
        #expect(try timeRepository.activeSegments().isEmpty)
    }
}
