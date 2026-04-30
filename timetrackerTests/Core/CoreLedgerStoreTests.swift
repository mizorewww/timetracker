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
        #expect(repository.pausedSessionsCallCount == 1)
        #expect(repository.rangeSegmentsCallCount == 1)
        #expect(repository.allSegmentsCallCount == 0)
        #expect(repository.sessionsCallCount == 0)
    }
}

private final class LedgerRefreshSpyRepository: TimeTrackingRepository {
    var activeSegmentsCallCount = 0
    var pausedSessionsCallCount = 0
    var rangeSegmentsCallCount = 0
    var allSegmentsCallCount = 0
    var sessionsCallCount = 0

    func activeSegments() throws -> [TimeSegment] {
        activeSegmentsCallCount += 1
        return []
    }

    func pausedSessions() throws -> [TimeSession] {
        pausedSessionsCallCount += 1
        return []
    }

    func sessions() throws -> [TimeSession] {
        sessionsCallCount += 1
        return []
    }

    func segments(from: Date, to: Date) throws -> [TimeSegment] {
        try segments(from: from, to: to, now: Date())
    }

    func segments(from: Date, to: Date, now: Date) throws -> [TimeSegment] {
        rangeSegmentsCallCount += 1
        return []
    }

    func allSegments() throws -> [TimeSegment] {
        allSegmentsCallCount += 1
        return []
    }

    func startTask(taskID: UUID, source: TimeSessionSource) throws -> TimeSegment {
        fatalError("Unused in LedgerRefreshSpyRepository")
    }

    func stopSegment(segmentID: UUID) throws {}

    func updateSegment(segmentID: UUID, taskID: UUID, startedAt: Date, endedAt: Date?, note: String?) throws {}

    func softDeleteSegment(segmentID: UUID) throws {}

    func stopSession(sessionID: UUID) throws {}

    func pauseSession(sessionID: UUID) throws {}

    func resumeSession(sessionID: UUID) throws -> TimeSegment? {
        nil
    }

    func addManualSegment(taskID: UUID, startedAt: Date, endedAt: Date, note: String?) throws -> TimeSegment {
        fatalError("Unused in LedgerRefreshSpyRepository")
    }
}
