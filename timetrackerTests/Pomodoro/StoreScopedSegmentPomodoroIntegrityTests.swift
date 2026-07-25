import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedSegmentPomodoroIntegrityTests {
    @Test
    func editingClosedSiblingRebindsWithoutCancellingActiveFocus() throws {
        let context = try makeTestContext()
        let container = context.container
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "fixture"
        )
        let source = try makeTask("Source", repository: taskRepository)
        let target = try makeTask("Target", repository: taskRepository)
        let startedAt = Date(timeIntervalSinceReferenceDate: 8_000_000)
        let fixture = try insertStoreScopedSegmentPomodoroFixture(
            context: context,
            task: source,
            sessionStartedAt: startedAt,
            activeSegmentStartedAt: startedAt.addingTimeInterval(120),
            closedSegmentEnd: startedAt.addingTimeInterval(60)
        )
        let closedSegmentID = try #require(fixture.closedSegmentID)
        var draft = try makeStoreScopedSegmentDraft(
            segmentID: closedSegmentID,
            container: container
        )
        #expect(draft.wasActive == false)
        draft.taskID = target.id
        draft.note = "Keep focusing"

        _ = try makeStoreScopedSegmentCoordinator(
            container: container,
            now: startedAt.addingTimeInterval(180)
        ).update(
            draft: draft,
            taskID: target.id
        )

        let freshContext = ModelContext(container)
        let timeRepository = timeRepository(freshContext)
        let segments = try timeRepository.segments(
            sessionIDs: [fixture.sessionID]
        )
        let active = try #require(
            segments.first { $0.id == fixture.activeSegmentID }
        )
        let session = try #require(
            try timeRepository.sessions(ids: [fixture.sessionID]).first
        )
        let run = try #require(
            try pomodoroRepository(freshContext).run(id: fixture.runID)
        )
        #expect(segments.allSatisfy { $0.taskID == target.id })
        #expect(active.endedAt == nil)
        #expect(session.taskID == target.id)
        #expect(session.endedAt == nil)
        #expect(session.note == "Keep focusing")
        #expect(run.taskID == target.id)
        #expect(run.state == .focusing)
        #expect(run.endedAt == nil)
        #expect(run.deletedAt == nil)
    }

    @Test
    func duplicateRunsInAdmissionSessionRejectWholeEdit() throws {
        let context = try makeTestContext()
        let container = context.container
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "fixture"
        )
        let subjectTask = try makeTask("Subject", repository: taskRepository)
        let otherTask = try makeTask("Other focus", repository: taskRepository)
        let startedAt = Date(timeIntervalSinceReferenceDate: 9_000_000)
        let subject = try SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "fixture",
            nowProvider: { startedAt }
        ).startTask(taskID: subjectTask.id, source: .timer)
        let fixture = try insertStoreScopedSegmentPomodoroFixture(
            context: context,
            task: otherTask,
            sessionStartedAt: startedAt,
            activeSegmentStartedAt: startedAt
        )
        let duplicateRun = PomodoroRun(
            taskID: otherTask.id,
            focus: 25 * 60,
            breakSeconds: 5 * 60,
            targetRounds: 1,
            deviceID: "duplicate"
        )
        duplicateRun.sessionID = fixture.sessionID
        duplicateRun.startedAt = startedAt
        duplicateRun.state = .interrupted
        context.insert(duplicateRun)
        try context.save()
        try setTestAllowParallelTimers(false, context: context)
        var draft = try makeStoreScopedSegmentDraft(
            segmentID: subject.id,
            container: container
        )
        draft.note = "Must roll back"

        #expect(throws: SegmentMutationError.inconsistentSession) {
            _ = try makeStoreScopedSegmentCoordinator(
                container: container,
                now: startedAt.addingTimeInterval(60)
            ).update(
                draft: draft,
                taskID: subjectTask.id
            )
        }

        let freshContext = ModelContext(container)
        let freshTimeRepository = timeRepository(freshContext)
        #expect(
            try Set(freshTimeRepository.activeSegments().map(\.id))
                == [subject.id, fixture.activeSegmentID]
        )
        let subjectSession = try #require(
            try freshTimeRepository.sessions(ids: [subject.sessionID]).first
        )
        #expect(subjectSession.note == nil)
        let activeRuns = try pomodoroRepository(freshContext).activeRuns()
            .filter { $0.sessionID == fixture.sessionID }
        #expect(Set(activeRuns.map(\.id)) == [fixture.runID, duplicateRun.id])
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

    private func timeRepository(
        _ context: ModelContext
    ) -> SwiftDataTimeTrackingRepository {
        SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "fixture"
        )
    }

    private func pomodoroRepository(
        _ context: ModelContext
    ) -> SwiftDataPomodoroRepository {
        SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository(context),
            deviceID: "fixture"
        )
    }
}
