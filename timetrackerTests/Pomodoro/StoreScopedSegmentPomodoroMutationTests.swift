import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedSegmentPomodoroMutationTests {
    @Test
    func activeSessionRebindUpdatesEverySiblingAndLinkedRun() throws {
        let context = try makeTestContext()
        let container = context.container
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "fixture")
        let source = try makeTask("Source", repository: taskRepository)
        let target = try makeTask("Target", repository: taskRepository)
        let sessionStart = Date(timeIntervalSinceReferenceDate: 5_000_000)
        let fixture = try insertFixture(
            context: context,
            task: source,
            sessionStartedAt: sessionStart,
            activeSegmentStartedAt: sessionStart.addingTimeInterval(120),
            closedSegmentEnd: sessionStart.addingTimeInterval(60)
        )
        var draft = try makeDraft(segmentID: fixture.activeSegmentID, container: container)
        draft.taskID = target.id
        draft.startedAt = sessionStart.addingTimeInterval(90)
        draft.note = "Rebound session"

        let outcome = try makeCoordinator(
            container: container,
            now: sessionStart.addingTimeInterval(300)
        ).update(draft: draft, taskID: target.id)

        let freshContext = ModelContext(container)
        let timeRepo = timeRepository(freshContext)
        let segments = try timeRepo.segments(sessionIDs: [fixture.sessionID])
        let session = try #require(try timeRepo.sessions(ids: [fixture.sessionID]).first)
        let run = try #require(try pomodoroRepository(freshContext).run(id: fixture.runID))
        #expect(segments.count == 2)
        #expect(segments.allSatisfy { $0.taskID == target.id })
        #expect(session.taskID == target.id)
        #expect(session.titleSnapshot == target.title)
        #expect(session.note == "Rebound session")
        #expect(run.taskID == target.id)
        #expect(run.clientMutationID != fixture.originalRunMutationID)
        #expect(outcome.referencedTaskIDs == [source.id, target.id])
    }

    @Test
    func closingShortActivePomodoroPreservesHistory() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask(
            "Short focus",
            repository: SwiftDataTaskRepository(context: context, deviceID: "fixture")
        )
        let startedAt = Date(timeIntervalSinceReferenceDate: 6_000_000)
        let fixture = try insertFixture(
            context: context,
            task: task,
            sessionStartedAt: startedAt,
            activeSegmentStartedAt: startedAt
        )
        var draft = try makeDraft(segmentID: fixture.activeSegmentID, container: container)
        let endedAt = startedAt.addingTimeInterval(60)
        draft.endedAt = endedAt
        draft.isActive = false

        _ = try makeCoordinator(container: container, now: endedAt)
            .update(draft: draft, taskID: task.id)

        let freshContext = ModelContext(container)
        let timeRepo = timeRepository(freshContext)
        let segment = try #require(try timeRepo.allSegments().first { $0.id == fixture.activeSegmentID })
        let run = try #require(try pomodoroRepository(freshContext).run(id: fixture.runID))
        #expect(segment.endedAt == endedAt)
        #expect(segment.deletedAt == nil)
        #expect(run.state == .cancelled)
        #expect(run.endedAt == endedAt)
        #expect(run.deletedAt == nil)
    }

    @Test
    func deletingActivePomodoroTombstonesWholeSession() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask(
            "Delete focus",
            repository: SwiftDataTaskRepository(context: context, deviceID: "fixture")
        )
        let startedAt = Date(timeIntervalSinceReferenceDate: 7_000_000)
        let fixture = try insertFixture(
            context: context,
            task: task,
            sessionStartedAt: startedAt,
            activeSegmentStartedAt: startedAt.addingTimeInterval(120),
            closedSegmentEnd: startedAt.addingTimeInterval(60)
        )
        let draft = try makeDraft(segmentID: fixture.activeSegmentID, container: container)

        let outcome = try makeCoordinator(
            container: container,
            now: startedAt.addingTimeInterval(180)
        ).delete(segmentID: fixture.activeSegmentID, expectedBaseline: draft.baseline)

        let rawContext = ModelContext(container)
        let segments = try rawContext.fetch(FetchDescriptor<TimeSegment>())
            .filter { $0.sessionID == fixture.sessionID }
        let session = try #require(
            try rawContext.fetch(FetchDescriptor<TimeSession>()).first { $0.id == fixture.sessionID }
        )
        let run = try #require(
            try rawContext.fetch(FetchDescriptor<PomodoroRun>()).first { $0.id == fixture.runID }
        )
        #expect(segments.count == 2)
        #expect(segments.allSatisfy { $0.deletedAt != nil })
        #expect(session.deletedAt != nil)
        #expect(run.state == .cancelled)
        #expect(run.deletedAt != nil)
        #expect(outcome.segmentChanges.count == 2)
        #expect(outcome.pomodoroChanges.count == 1)
    }

    @Test
    func editingClosedSiblingRebindsWithoutCancellingActiveFocus() throws {
        let context = try makeTestContext()
        let container = context.container
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "fixture")
        let source = try makeTask("Source", repository: taskRepository)
        let target = try makeTask("Target", repository: taskRepository)
        let startedAt = Date(timeIntervalSinceReferenceDate: 8_000_000)
        let fixture = try insertFixture(
            context: context,
            task: source,
            sessionStartedAt: startedAt,
            activeSegmentStartedAt: startedAt.addingTimeInterval(120),
            closedSegmentEnd: startedAt.addingTimeInterval(60)
        )
        let closedSegmentID = try #require(fixture.closedSegmentID)
        var draft = try makeDraft(segmentID: closedSegmentID, container: container)
        draft.taskID = target.id
        draft.note = "Keep focusing"

        _ = try makeCoordinator(container: container, now: startedAt.addingTimeInterval(180))
            .update(draft: draft, taskID: target.id)

        let freshContext = ModelContext(container)
        let run = try #require(try pomodoroRepository(freshContext).run(id: fixture.runID))
        #expect(run.taskID == target.id)
        #expect(run.state == .focusing)
        #expect(run.endedAt == nil)
    }

    @Test
    func duplicateRunsInAdmissionSessionRejectWholeEdit() throws {
        let context = try makeTestContext()
        let container = context.container
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "fixture")
        let subjectTask = try makeTask("Subject", repository: taskRepository)
        let otherTask = try makeTask("Other focus", repository: taskRepository)
        let startedAt = Date(timeIntervalSinceReferenceDate: 9_000_000)
        let subject = try SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "fixture",
            nowProvider: { startedAt }
        ).startTask(taskID: subjectTask.id, source: .timer)
        let fixture = try insertFixture(
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
        var draft = try makeDraft(segmentID: subject.id, container: container)
        draft.note = "Must roll back"

        #expect(throws: SegmentMutationError.inconsistentSession) {
            _ = try makeCoordinator(container: container, now: startedAt.addingTimeInterval(60))
                .update(draft: draft, taskID: subjectTask.id)
        }
    }

    private struct Fixture {
        let sessionID: UUID
        let activeSegmentID: UUID
        let closedSegmentID: UUID?
        let runID: UUID
        let originalRunMutationID: UUID
    }

    private func insertFixture(
        context: ModelContext,
        task: TaskNode,
        sessionStartedAt: Date,
        activeSegmentStartedAt: Date,
        closedSegmentEnd: Date? = nil
    ) throws -> Fixture {
        let session = TimeSession(
            taskID: task.id,
            source: .pomodoro,
            deviceID: "fixture",
            startedAt: sessionStartedAt,
            titleSnapshot: task.title
        )
        let closedSegment = closedSegmentEnd.map { end in
            TimeSegment(
                sessionID: session.id,
                taskID: task.id,
                source: .pomodoro,
                deviceID: "fixture",
                startedAt: sessionStartedAt,
                endedAt: end
            )
        }
        let activeSegment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .pomodoro,
            deviceID: "fixture",
            startedAt: activeSegmentStartedAt
        )
        let run = PomodoroRun(
            taskID: task.id,
            focus: 25 * 60,
            breakSeconds: 5 * 60,
            targetRounds: 1,
            deviceID: "fixture"
        )
        run.sessionID = session.id
        run.startedAt = sessionStartedAt
        run.state = .focusing
        context.insert(session)
        if let closedSegment {
            context.insert(closedSegment)
        }
        context.insert(activeSegment)
        context.insert(run)
        try context.save()
        return Fixture(
            sessionID: session.id,
            activeSegmentID: activeSegment.id,
            closedSegmentID: closedSegment?.id,
            runID: run.id,
            originalRunMutationID: run.clientMutationID
        )
    }

    private func makeDraft(segmentID: UUID, container: ModelContainer) throws -> SegmentEditorDraft {
        let context = ModelContext(container)
        let timeRepo = timeRepository(context)
        let segment = try #require(try timeRepo.segments(ids: [segmentID]).first)
        let session = try #require(try timeRepo.sessions(ids: [segment.sessionID]).first)
        let run = try pomodoroRepository(context).activeRuns().first {
            $0.sessionID == segment.sessionID
        }
        return SegmentEditorDraft(
            segment: segment,
            note: session.note ?? "",
            sessionMutationID: session.clientMutationID,
            pomodoroPhase: run.map(PomodoroPhaseToken.init)
        )
    }

    private func makeCoordinator(
        container: ModelContainer,
        now: Date
    ) -> StoreScopedSegmentCommandCoordinator {
        StoreScopedSegmentCommandCoordinator(
            session: .testHarness(container),
            deviceID: "coordinator",
            nowProvider: { now }
        )
    }

    private func makeTask(_ title: String, repository: SwiftDataTaskRepository) throws -> TaskNode {
        try repository.createTask(title: title, parentID: nil)
    }

    private func timeRepository(_ context: ModelContext) -> SwiftDataTimeTrackingRepository {
        SwiftDataTimeTrackingRepository(context: context, deviceID: "fixture")
    }

    private func pomodoroRepository(_ context: ModelContext) -> SwiftDataPomodoroRepository {
        SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository(context),
            deviceID: "fixture"
        )
    }
}
