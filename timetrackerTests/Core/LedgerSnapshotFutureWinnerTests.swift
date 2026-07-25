import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct LedgerSnapshotFutureWinnerTests {
    @Test
    func strictMutationDateSurvivesCloudMillisecondRepresentation() {
        let observed = Date(
            timeIntervalSinceReferenceDate: 800_000_000.0009999
        )
        let preferred = observed.addingTimeInterval(0.0001)

        let mutationDate = PersistentLWWMutationDate.strictlyDominating(
            preferred: preferred,
            observed: observed
        )

        #expect(mutationDate > observed)
        #expect(cloudMilliseconds(mutationDate) > cloudMilliseconds(observed))
    }

    @Test
    func restoreIntoEmptyStoreAdvancesSnapshotRowsBeforeRedelivery() throws {
        let source = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: source,
            deviceID: "source"
        ).createTask(
            title: "Restore winner",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let startedAt = Date(timeIntervalSinceReferenceDate: 12_000_000)
        let endedAt = startedAt.addingTimeInterval(120)
        let segment = try SwiftDataTimeTrackingRepository(
            context: source,
            deviceID: "source",
            nowProvider: { endedAt }
        ).addManualSegment(
            taskID: task.id,
            startedAt: startedAt,
            endedAt: endedAt,
            note: "Keep closed"
        )
        let session = try #require(
            try SwiftDataTimeTrackingRepository(
                context: source,
                deviceID: "source",
                nowProvider: { endedAt }
            ).sessions(ids: [segment.sessionID]).first
        )
        let futureDate = endedAt.addingTimeInterval(3600)
        session.updatedAt = futureDate
        segment.updatedAt = futureDate
        try source.save()
        let snapshot = try SyncDataSnapshot.capture(context: source)
        let target = try makeTestContext()

        try snapshot.restoreAsLocalWinner(
            context: target,
            now: endedAt.addingTimeInterval(10)
        )

        var restoredSessions = try target.fetch(
            FetchDescriptor<TimeSession>()
        )
        var restoredSegments = try target.fetch(
            FetchDescriptor<TimeSegment>()
        )
        let restoredSession = try #require(
            restoredSessions.deduplicatedByID().first {
                $0.id == session.id
            }
        )
        let restoredSegment = try #require(
            restoredSegments.deduplicatedByID().first {
                $0.id == segment.id
            }
        )
        #expect(restoredSession.updatedAt > futureDate)
        #expect(restoredSegment.updatedAt > futureDate)

        let redeliveredSession = TimeSession(
            taskID: task.id,
            source: .manual,
            deviceID: "zzzz-redelivered",
            startedAt: startedAt,
            titleSnapshot: task.title
        )
        redeliveredSession.id = session.id
        redeliveredSession.note = "Stale open"
        redeliveredSession.createdAt = session.createdAt
        redeliveredSession.updatedAt = futureDate
        let redeliveredSegment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .manual,
            deviceID: "zzzz-redelivered",
            startedAt: startedAt
        )
        redeliveredSegment.id = segment.id
        redeliveredSegment.createdAt = segment.createdAt
        redeliveredSegment.updatedAt = futureDate
        target.insert(redeliveredSession)
        target.insert(redeliveredSegment)
        try target.save()

        restoredSessions = try target.fetch(FetchDescriptor<TimeSession>())
        restoredSegments = try target.fetch(FetchDescriptor<TimeSegment>())
        #expect(
            restoredSessions.deduplicatedByID().first {
                $0.id == session.id
            }?.endedAt == endedAt
        )
        #expect(
            restoredSegments.deduplicatedByID().first {
                $0.id == segment.id
            }?.endedAt == endedAt
        )
    }

    @Test
    func emptyRestoreTombstonesFutureLedgerRowsAndSurvivesRedelivery() throws {
        let source = try makeTestContext()
        let emptySnapshot = try SyncDataSnapshot.capture(context: source)
        let target = try makeTestContext()
        let taskID = UUID()
        let startedAt = Date(timeIntervalSinceReferenceDate: 11_000_000)
        let endedAt = startedAt.addingTimeInterval(120)
        let restoreDate = endedAt.addingTimeInterval(100)
        let futureDate = restoreDate.addingTimeInterval(500)
        let session = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "future",
            startedAt: startedAt
        )
        session.endedAt = endedAt
        session.updatedAt = futureDate
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "future",
            startedAt: startedAt,
            endedAt: endedAt
        )
        segment.updatedAt = futureDate
        target.insert(session)
        target.insert(segment)
        try target.save()

        try emptySnapshot.restoreAsLocalWinner(
            context: target,
            now: restoreDate
        )
        var sessions = try target.fetch(FetchDescriptor<TimeSession>())
        var segments = try target.fetch(FetchDescriptor<TimeSegment>())
        let deletedSession = try #require(
            sessions.deduplicatedByID().first { $0.id == session.id }
        )
        let deletedSegment = try #require(
            segments.deduplicatedByID().first { $0.id == segment.id }
        )
        #expect(deletedSession.deletedAt != nil)
        #expect(deletedSession.updatedAt > futureDate)
        #expect(deletedSegment.deletedAt != nil)
        #expect(deletedSegment.updatedAt > futureDate)

        let redeliveredSession = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "redelivered",
            startedAt: startedAt
        )
        redeliveredSession.id = session.id
        redeliveredSession.endedAt = endedAt
        redeliveredSession.updatedAt = futureDate
        let redeliveredSegment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "redelivered",
            startedAt: startedAt,
            endedAt: endedAt
        )
        redeliveredSegment.id = segment.id
        redeliveredSegment.updatedAt = futureDate
        target.insert(redeliveredSession)
        target.insert(redeliveredSegment)
        try target.save()

        sessions = try target.fetch(FetchDescriptor<TimeSession>())
        segments = try target.fetch(FetchDescriptor<TimeSegment>())
        #expect(
            sessions.visibleDeduplicatedByID().contains {
                $0.id == session.id
            } == false
        )
        #expect(
            segments.visibleDeduplicatedByID().contains {
                $0.id == segment.id
            } == false
        )
        let restoredSnapshot = try SyncDataSnapshot.capture(context: target)
        #expect(
            restoredSnapshot.sessions.first {
                $0.id == session.id
            }?.deletedAt != nil
        )
        #expect(
            restoredSnapshot.segments.first {
                $0.id == segment.id
            }?.deletedAt != nil
        )
    }

    private func cloudMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }
}
