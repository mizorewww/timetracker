import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TimeTrackingFutureWinnerMutationTests {
    @Test
    func mutationsStayAheadOfFutureStampedStaleDuplicates() throws {
        // 1. Edit
        let editFixture = try makeFixture(
            title: "Future edit",
            startedAt: Date(timeIntervalSinceReferenceDate: 800_100_000)
        )
        let editedStart = editFixture.startedAt.addingTimeInterval(1)
        try repository(editFixture).updateSegment(
            segmentID: editFixture.segmentID,
            taskID: editFixture.taskID,
            startedAt: editedStart,
            endedAt: nil,
            note: "Edited"
        )
        try verifyDominanceAfterStaleCopies(editFixture) { segment, session, _ in
            #expect(segment.startedAt == editedStart)
            #expect(session.startedAt == editedStart)
            #expect(session.note == "Edited")
        }

        // 2. Soft delete
        let deleteFixture = try makeFixture(
            title: "Future delete",
            startedAt: Date(timeIntervalSinceReferenceDate: 800_200_000)
        )
        try repository(deleteFixture).softDeleteSegment(segmentID: deleteFixture.segmentID)
        try verifyDominanceAfterStaleCopies(deleteFixture) { segment, session, context in
            #expect(segment.deletedAt != nil)
            #expect(session.deletedAt != nil)
            let visibleSegments = try context.fetch(FetchDescriptor<TimeSegment>())
                .visibleDeduplicatedByID()
            #expect(visibleSegments.contains { $0.id == deleteFixture.segmentID } == false)
        }

        // 3. Session stop
        let stopFixture = try makeFixture(
            title: "Future session stop",
            startedAt: Date(timeIntervalSinceReferenceDate: 800_300_000)
        )
        try repository(stopFixture).stopSession(sessionID: stopFixture.sessionID)
        try verifyDominanceAfterStaleCopies(stopFixture) { segment, session, _ in
            #expect(segment.endedAt == stopFixture.mutationDate)
            #expect(session.endedAt == stopFixture.mutationDate)
        }
    }

    private struct Fixture {
        let container: ModelContainer
        let taskID: UUID
        let sessionID: UUID
        let segmentID: UUID
        let title: String
        let startedAt: Date
        let sessionCreatedAt: Date
        let segmentCreatedAt: Date
        let futureDate: Date
        let mutationDate: Date
    }

    private func makeFixture(title: String, startedAt: Date) throws -> Fixture {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "fixture")
            .createTask(title: title, parentID: nil)
        let repo = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "fixture",
            nowProvider: { startedAt }
        )
        let segment = try repo.startTask(taskID: task.id, source: .timer)
        let session = try #require(try repo.sessions(ids: [segment.sessionID]).first)
        let mutationDate = startedAt.addingTimeInterval(30)
        let futureDate = mutationDate.addingTimeInterval(3600)
        segment.updatedAt = futureDate
        session.updatedAt = futureDate
        try context.save()
        return Fixture(
            container: context.container,
            taskID: task.id,
            sessionID: session.id,
            segmentID: segment.id,
            title: task.title,
            startedAt: startedAt,
            sessionCreatedAt: session.createdAt,
            segmentCreatedAt: segment.createdAt,
            futureDate: futureDate,
            mutationDate: mutationDate
        )
    }

    private func repository(_ fixture: Fixture) -> SwiftDataTimeTrackingRepository {
        SwiftDataTimeTrackingRepository(
            context: ModelContext(fixture.container),
            deviceID: "mutation",
            nowProvider: { fixture.mutationDate }
        )
    }

    private func verifyDominanceAfterStaleCopies(
        _ fixture: Fixture,
        assertions: (TimeSegment, TimeSession, ModelContext) throws -> Void
    ) throws {
        let seedContext = ModelContext(fixture.container)
        let session = TimeSession(
            taskID: fixture.taskID,
            source: .timer,
            deviceID: "zzzz-stale-session",
            startedAt: fixture.startedAt,
            titleSnapshot: fixture.title
        )
        session.id = fixture.sessionID
        session.note = "Stale"
        session.createdAt = fixture.sessionCreatedAt
        session.updatedAt = fixture.futureDate
        let segment = TimeSegment(
            sessionID: fixture.sessionID,
            taskID: fixture.taskID,
            source: .timer,
            deviceID: "zzzz-stale-segment",
            startedAt: fixture.startedAt
        )
        segment.id = fixture.segmentID
        segment.createdAt = fixture.segmentCreatedAt
        segment.updatedAt = fixture.futureDate
        seedContext.insert(session)
        seedContext.insert(segment)
        try seedContext.save()

        let verifyContext = ModelContext(fixture.container)
        let winningSegment = try #require(
            try verifyContext.fetch(FetchDescriptor<TimeSegment>())
                .deduplicatedByID()
                .first { $0.id == fixture.segmentID }
        )
        let winningSession = try #require(
            try verifyContext.fetch(FetchDescriptor<TimeSession>())
                .deduplicatedByID()
                .first { $0.id == fixture.sessionID }
        )
        #expect(winningSegment.updatedAt > fixture.futureDate)
        #expect(winningSession.updatedAt > fixture.futureDate)
        try assertions(winningSegment, winningSession, verifyContext)
    }
}
