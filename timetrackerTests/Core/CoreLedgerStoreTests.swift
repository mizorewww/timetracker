import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreLedgerStoreTests {
    @Test @MainActor
    func ledgerVisibleRefreshDoesNotFetchFullHistory() throws {
        let repository = LedgerRefreshSpyRepository()
        var store = LedgerStore()

        try store.refreshVisible(repository: repository, now: Date(timeIntervalSince1970: 10_000))

        #expect(repository.activeSegmentsCallCount == 1)
        #expect(repository.rangeSegmentsCallCount == 1)
        #expect(repository.allSegmentsCallCount == 0)
        #expect(repository.sessionsCallCount == 0)
    }

    @Test @MainActor
    func ledgerRangeHistoryRefreshMergesAffectedRangeWithoutFullHistoryFetch() throws {
        let taskID = UUID()
        let oldSession = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: Date(timeIntervalSince1970: 100)
        )
        oldSession.endedAt = Date(timeIntervalSince1970: 200)
        let oldSegment = TimeSegment(
            sessionID: oldSession.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: Date(timeIntervalSince1970: 200)
        )

        let unchangedSession = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: Date(timeIntervalSince1970: 10_000)
        )
        unchangedSession.endedAt = Date(timeIntervalSince1970: 10_100)
        let unchangedSegment = TimeSegment(
            sessionID: unchangedSession.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: Date(timeIntervalSince1970: 10_000),
            endedAt: Date(timeIntervalSince1970: 10_100)
        )

        let updatedSession = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: Date(timeIntervalSince1970: 120)
        )
        updatedSession.id = oldSession.id
        updatedSession.endedAt = Date(timeIntervalSince1970: 240)
        let updatedSegment = TimeSegment(
            sessionID: updatedSession.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: Date(timeIntervalSince1970: 120),
            endedAt: Date(timeIntervalSince1970: 240)
        )
        updatedSegment.id = oldSegment.id

        let repository = LedgerRefreshSpyRepository()
        repository.fullSegments = [oldSegment, unchangedSegment]
        repository.fullSessions = [oldSession, unchangedSession]

        var store = LedgerStore()
        try store.refreshHistory(repository: repository)

        repository.resetCounters()
        repository.rangeSegments = [updatedSegment]
        repository.sessionsByID = [updatedSession.id: updatedSession]

        try store.refreshHistoryRanges(
            repository: repository,
            ranges: [StoreInvalidationRange(start: Date(timeIntervalSince1970: 90), end: Date(timeIntervalSince1970: 250))],
            now: Date(timeIntervalSince1970: 300)
        )

        #expect(repository.rangeSegmentsCallCount == 1)
        #expect(repository.sessionsByIDsCallCount == 1)
        #expect(repository.allSegmentsCallCount == 0)
        #expect(repository.sessionsCallCount == 0)
        #expect(store.allSegments.map(\.id) == [updatedSegment.id, unchangedSegment.id])
        #expect(store.sessions.map(\.id).contains(updatedSession.id))
        #expect(store.sessions.map(\.id).contains(unchangedSession.id))
    }
}

private final class LedgerRefreshSpyRepository: TimeTrackingRepository {
    var activeSegmentsCallCount = 0
    var rangeSegmentsCallCount = 0
    var allSegmentsCallCount = 0
    var sessionsCallCount = 0
    var sessionsByIDsCallCount = 0

    var fullSegments: [TimeSegment] = []
    var fullSessions: [TimeSession] = []
    var rangeSegments: [TimeSegment] = []
    var sessionsByID: [UUID: TimeSession] = [:]

    func resetCounters() {
        activeSegmentsCallCount = 0
        rangeSegmentsCallCount = 0
        allSegmentsCallCount = 0
        sessionsCallCount = 0
        sessionsByIDsCallCount = 0
    }

    func activeSegments() throws -> [TimeSegment] {
        activeSegmentsCallCount += 1
        return []
    }

    func sessions() throws -> [TimeSession] {
        sessionsCallCount += 1
        return fullSessions
    }

    func sessions(ids: Set<UUID>) throws -> [TimeSession] {
        sessionsByIDsCallCount += 1
        return ids.compactMap { sessionsByID[$0] }
    }

    func segments(from: Date, to: Date) throws -> [TimeSegment] {
        try segments(from: from, to: to, now: Date())
    }

    func segments(from: Date, to: Date, now: Date) throws -> [TimeSegment] {
        rangeSegmentsCallCount += 1
        return rangeSegments
    }

    func allSegments() throws -> [TimeSegment] {
        allSegmentsCallCount += 1
        return fullSegments
    }

    func startTask(taskID: UUID, source: TimeSessionSource) throws -> TimeSegment {
        fatalError("Unused in LedgerRefreshSpyRepository")
    }

    func stopSegment(segmentID: UUID) throws {}

    func updateSegment(segmentID: UUID, taskID: UUID, startedAt: Date, endedAt: Date?, note: String?) throws {}

    func softDeleteSegment(segmentID: UUID) throws {}

    func stopSession(sessionID: UUID) throws {}

    func addManualSegment(taskID: UUID, startedAt: Date, endedAt: Date, note: String?) throws -> TimeSegment {
        fatalError("Unused in LedgerRefreshSpyRepository")
    }
}
