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
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: "fixture"
        )
        let source = try makeTask("Source", repository: taskRepository)
        let target = try makeTask("Target", repository: taskRepository)
        let sessionStart = Date(timeIntervalSinceReferenceDate: 5_000_000)
        let fixture = try insertStoreScopedSegmentPomodoroFixture(
            context: context,
            task: source,
            sessionStartedAt: sessionStart,
            activeSegmentStartedAt: sessionStart.addingTimeInterval(120),
            closedSegmentEnd: sessionStart.addingTimeInterval(60)
        )
        var draft = try makeStoreScopedSegmentDraft(
            segmentID: fixture.activeSegmentID,
            container: container
        )
        draft.taskID = target.id
        draft.startedAt = sessionStart.addingTimeInterval(90)
        draft.note = "Rebound session"

        let outcome = try makeStoreScopedSegmentCoordinator(
            container: container,
            now: sessionStart.addingTimeInterval(300)
        ).update(
            draft: draft,
            taskID: target.id
        )

        let freshContext = ModelContext(container)
        let timeRepository = timeRepository(freshContext)
        let segments = try timeRepository.segments(
            sessionIDs: [fixture.sessionID]
        )
        let session = try #require(
            try timeRepository.sessions(ids: [fixture.sessionID]).first
        )
        let run = try #require(
            try pomodoroRepository(freshContext).run(id: fixture.runID)
        )
        #expect(segments.count == 2)
        #expect(segments.allSatisfy { $0.taskID == target.id })
        #expect(session.taskID == target.id)
        #expect(session.titleSnapshot == target.title)
        #expect(session.note == "Rebound session")
        #expect(session.startedAt == sessionStart)
        #expect(session.endedAt == nil)
        #expect(run.taskID == target.id)
        #expect(run.startedAt == sessionStart)
        #expect(run.clientMutationID != fixture.originalRunMutationID)
        #expect(Set(outcome.segmentChanges.map(\.before.segmentID)) == Set(segments.map(\.id)))
        #expect(outcome.pomodoroChanges.map(\.before.runID) == [fixture.runID])
        #expect(outcome.referencedTaskIDs == [source.id, target.id])
    }

    @Test
    func closingShortActivePomodoroPreservesHistory() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask(
            "Short focus",
            repository: SwiftDataTaskRepository(
                context: context,
                deviceID: "fixture"
            )
        )
        let startedAt = Date(timeIntervalSinceReferenceDate: 6_000_000)
        let fixture = try insertStoreScopedSegmentPomodoroFixture(
            context: context,
            task: task,
            sessionStartedAt: startedAt,
            activeSegmentStartedAt: startedAt
        )
        var draft = try makeStoreScopedSegmentDraft(
            segmentID: fixture.activeSegmentID,
            container: container
        )
        let endedAt = startedAt.addingTimeInterval(60)
        draft.endedAt = endedAt
        draft.isActive = false

        let outcome = try makeStoreScopedSegmentCoordinator(
            container: container,
            now: endedAt
        ).update(
            draft: draft,
            taskID: task.id
        )

        let freshContext = ModelContext(container)
        let timeRepository = timeRepository(freshContext)
        let segment = try #require(
            try timeRepository.allSegments().first {
                $0.id == fixture.activeSegmentID
            }
        )
        let session = try #require(
            try timeRepository.sessions(ids: [fixture.sessionID]).first
        )
        let run = try #require(
            try pomodoroRepository(freshContext).run(id: fixture.runID)
        )
        #expect(segment.endedAt == endedAt)
        #expect(segment.deletedAt == nil)
        #expect(session.endedAt == endedAt)
        #expect(session.deletedAt == nil)
        #expect(run.state == .cancelled)
        #expect(run.endedAt == endedAt)
        #expect(run.deletedAt == nil)
        #expect(outcome.segmentChanges.map(\.before.segmentID) == [fixture.activeSegmentID])
        #expect(outcome.pomodoroChanges.map(\.before.runID) == [fixture.runID])
    }

    @Test
    func deletingActivePomodoroTombstonesWholeSession() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask(
            "Delete focus",
            repository: SwiftDataTaskRepository(
                context: context,
                deviceID: "fixture"
            )
        )
        let startedAt = Date(timeIntervalSinceReferenceDate: 7_000_000)
        let fixture = try insertStoreScopedSegmentPomodoroFixture(
            context: context,
            task: task,
            sessionStartedAt: startedAt,
            activeSegmentStartedAt: startedAt.addingTimeInterval(120),
            closedSegmentEnd: startedAt.addingTimeInterval(60)
        )
        let draft = try makeStoreScopedSegmentDraft(
            segmentID: fixture.activeSegmentID,
            container: container
        )

        let outcome = try makeStoreScopedSegmentCoordinator(
            container: container,
            now: startedAt.addingTimeInterval(180)
        ).delete(
            segmentID: fixture.activeSegmentID,
            expectedBaseline: draft.baseline
        )

        let rawContext = ModelContext(container)
        let segments = try rawContext.fetch(FetchDescriptor<TimeSegment>())
            .filter { $0.sessionID == fixture.sessionID }
        let session = try #require(
            try rawContext.fetch(FetchDescriptor<TimeSession>())
                .first { $0.id == fixture.sessionID }
        )
        let run = try #require(
            try rawContext.fetch(FetchDescriptor<PomodoroRun>())
                .first { $0.id == fixture.runID }
        )
        #expect(segments.count == 2)
        #expect(segments.allSatisfy { $0.deletedAt != nil })
        #expect(session.deletedAt != nil)
        #expect(run.state == .cancelled)
        #expect(run.deletedAt != nil)
        #expect(outcome.segmentChanges.count == 2)
        #expect(outcome.segmentChanges.allSatisfy { $0.after == nil })
        #expect(outcome.pomodoroChanges.count == 1)
        #expect(outcome.pomodoroChanges.first?.after == nil)
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
