import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TimeTrackingFutureWinnerMutationTests {
    @Test
    func editStaysAheadOfTheFutureActiveVersion() throws {
        let fixture = try makeFixture(
            title: "Future edit",
            startedAt: Date(timeIntervalSinceReferenceDate: 800_100_000)
        )
        let editedStart = fixture.startedAt.addingTimeInterval(1)
        try repository(fixture, now: fixture.mutationDate).updateSegment(
            segmentID: fixture.segmentID,
            taskID: fixture.taskID,
            startedAt: editedStart,
            endedAt: nil,
            note: "Edited"
        )

        var context = ModelContext(fixture.container)
        var segment = try canonicalSegment(fixture, context: context)
        var session = try canonicalSession(fixture, context: context)
        #expect(segment.startedAt == editedStart)
        #expect(segment.updatedAt > fixture.futureDate)
        #expect(session.startedAt == editedStart)
        #expect(session.note == "Edited")
        #expect(session.updatedAt > fixture.futureDate)

        insertStaleOpenCopies(fixture, context: context)
        try context.save()

        context = ModelContext(fixture.container)
        segment = try canonicalSegment(fixture, context: context)
        session = try canonicalSession(fixture, context: context)
        #expect(segment.startedAt == editedStart)
        #expect(session.startedAt == editedStart)
        #expect(session.note == "Edited")
    }

    @Test
    func deletionStaysAheadOfTheFutureVisibleVersion() throws {
        let fixture = try makeFixture(
            title: "Future delete",
            startedAt: Date(timeIntervalSinceReferenceDate: 800_200_000)
        )
        try repository(fixture, now: fixture.mutationDate)
            .softDeleteSegment(segmentID: fixture.segmentID)

        var context = ModelContext(fixture.container)
        let segment = try canonicalSegment(fixture, context: context)
        let session = try canonicalSession(fixture, context: context)
        #expect(segment.deletedAt != nil)
        #expect(segment.updatedAt > fixture.futureDate)
        #expect(session.deletedAt != nil)
        #expect(session.updatedAt > fixture.futureDate)

        insertStaleOpenCopies(fixture, context: context)
        try context.save()

        context = ModelContext(fixture.container)
        #expect(
            try context.fetch(FetchDescriptor<TimeSegment>())
                .visibleDeduplicatedByID()
                .contains { $0.id == fixture.segmentID } == false
        )
        #expect(
            try context.fetch(FetchDescriptor<TimeSession>())
                .visibleDeduplicatedByID()
                .contains { $0.id == fixture.sessionID } == false
        )
    }

    @Test
    func sessionStopStaysAheadOfTheFutureActiveVersion() throws {
        let fixture = try makeFixture(
            title: "Future session stop",
            startedAt: Date(timeIntervalSinceReferenceDate: 800_300_000)
        )
        try repository(fixture, now: fixture.mutationDate)
            .stopSession(sessionID: fixture.sessionID)

        var context = ModelContext(fixture.container)
        var segment = try canonicalSegment(fixture, context: context)
        var session = try canonicalSession(fixture, context: context)
        #expect(segment.endedAt == fixture.mutationDate)
        #expect(segment.updatedAt > fixture.futureDate)
        #expect(session.endedAt == fixture.mutationDate)
        #expect(session.updatedAt > fixture.futureDate)

        insertStaleOpenCopies(fixture, context: context)
        try context.save()

        context = ModelContext(fixture.container)
        segment = try canonicalSegment(fixture, context: context)
        session = try canonicalSession(fixture, context: context)
        #expect(segment.endedAt == fixture.mutationDate)
        #expect(session.endedAt == fixture.mutationDate)
        #expect(
            try repository(fixture, now: fixture.mutationDate)
                .activeSegments()
                .contains { $0.id == fixture.segmentID } == false
        )
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

    private func makeFixture(
        title: String,
        startedAt: Date
    ) throws -> Fixture {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "fixture"
        ).createTask(
            title: title,
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let segment = try SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "fixture",
            nowProvider: { startedAt }
        ).startTask(taskID: task.id, source: .timer)
        let session = try #require(
            try SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: "fixture",
                nowProvider: { startedAt }
            ).sessions(ids: [segment.sessionID]).first
        )
        let mutationDate = startedAt.addingTimeInterval(30)
        let futureDate = mutationDate.addingTimeInterval(3_600)
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

    private func repository(
        _ fixture: Fixture,
        now: Date
    ) -> SwiftDataTimeTrackingRepository {
        SwiftDataTimeTrackingRepository(
            context: ModelContext(fixture.container),
            deviceID: "mutation",
            nowProvider: { now }
        )
    }

    private func canonicalSegment(
        _ fixture: Fixture,
        context: ModelContext
    ) throws -> TimeSegment {
        try #require(
            try context.fetch(FetchDescriptor<TimeSegment>())
                .deduplicatedByID()
                .first { $0.id == fixture.segmentID }
        )
    }

    private func canonicalSession(
        _ fixture: Fixture,
        context: ModelContext
    ) throws -> TimeSession {
        try #require(
            try context.fetch(FetchDescriptor<TimeSession>())
                .deduplicatedByID()
                .first { $0.id == fixture.sessionID }
        )
    }

    private func insertStaleOpenCopies(
        _ fixture: Fixture,
        context: ModelContext
    ) {
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
        context.insert(session)
        context.insert(segment)
    }
}
