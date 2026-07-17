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
        let rollupChange = try #require(store.rollupChanges.first { $0.id == oldSegment.id })
        #expect(rollupChange.before == LedgerSegmentSnapshot(oldSegment))
        #expect(rollupChange.after == LedgerSegmentSnapshot(updatedSegment))
    }

    @Test @MainActor
    func rangeRefreshCanRemoveAnActiveSegmentBeyondItsPreviousDayIndex() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstDay = Date(timeIntervalSince1970: 172_800)
        let secondDay = firstDay.addingTimeInterval(86_400)
        let taskID = UUID()
        let session = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: firstDay.addingTimeInterval(3_600)
        )
        let activeSegment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: session.startedAt
        )
        let repository = LedgerRefreshSpyRepository()
        repository.fullSegments = [activeSegment]
        repository.fullSessions = [session]

        var store = LedgerStore()
        try store.refreshHistory(
            repository: repository,
            now: firstDay.addingTimeInterval(12 * 3_600),
            calendar: calendar
        )
        repository.resetCounters()
        repository.rangeSegments = []

        try store.refreshHistoryRanges(
            repository: repository,
            ranges: [StoreInvalidationRange(
                start: secondDay,
                end: secondDay.addingTimeInterval(86_400)
            )],
            now: secondDay.addingTimeInterval(12 * 3_600)
        )

        #expect(store.segment(for: activeSegment.id) == nil)
        let change = try #require(store.rollupChanges.first { $0.id == activeSegment.id })
        #expect(change.before == LedgerSegmentSnapshot(activeSegment))
        #expect(change.after == nil)
        #expect(repository.allSegmentsCallCount == 0)
    }

    @Test @MainActor
    func indexedQueriesIncludeAnActiveSegmentAfterItCrossesIntoANewDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstDay = Date(timeIntervalSince1970: 172_800)
        let secondDay = firstDay.addingTimeInterval(86_400)
        let taskID = UUID()
        let session = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: firstDay.addingTimeInterval(3_600)
        )
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: session.startedAt
        )
        let repository = LedgerRefreshSpyRepository()
        repository.fullSegments = [segment]
        repository.fullSessions = [session]
        var store = LedgerStore()

        try store.refreshHistory(
            repository: repository,
            now: firstDay.addingTimeInterval(12 * 3_600),
            calendar: calendar
        )

        let queryNow = secondDay.addingTimeInterval(12 * 3_600)
        let interval = DateInterval(start: secondDay, end: secondDay.addingTimeInterval(86_400))
        #expect(store.segments(overlapping: interval, now: queryNow).map(\.id) == [segment.id])
        #expect(store.segments(forTaskIDs: [taskID]).map(\.id) == [segment.id])
        #expect(store.segments(forSessionID: session.id).map(\.id) == [segment.id])
        #expect(store.sessions(for: [session.id]).map(\.id) == [session.id])
    }

    @Test @MainActor
    func extremeHistoricalSegmentUsesOverflowIndexWithoutLosingQueryResults() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let start = try #require(
            calendar.date(from: DateComponents(year: 1900, month: 1, day: 1))
        )
        let end = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))
        )
        let queryDay = try #require(
            calendar.date(from: DateComponents(year: 2025, month: 6, day: 1))
        )
        let taskID = UUID()
        let session = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "legacy",
            startedAt: start
        )
        session.endedAt = end
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "legacy",
            startedAt: start,
            endedAt: end
        )
        let repository = LedgerRefreshSpyRepository()
        repository.fullSessions = [session]
        repository.fullSegments = [segment]
        var store = LedgerStore()

        try store.refreshHistory(repository: repository, now: end, calendar: calendar)

        #expect(store.segmentIDsByDay.isEmpty)
        #expect(store.longSpanSegmentIDs == [segment.id])
        let day = DateInterval(
            start: queryDay,
            end: try #require(calendar.date(byAdding: .day, value: 1, to: queryDay))
        )
        #expect(store.segments(overlapping: day, now: end).map(\.id) == [segment.id])
        let wholeHistory = DateInterval(
            start: start,
            end: try #require(calendar.date(byAdding: .day, value: 1, to: end))
        )
        #expect(store.segments(overlapping: wholeHistory, now: end).map(\.id) == [segment.id])
    }

    @Test @MainActor
    func historicalCutoffDoesNotExpandIndexedQueryToTheWholeLedger() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))
        )
        let liveNow = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 12))
        )
        let taskID = UUID()
        let sessions = (0..<40).map { offset in
            TimeSession(
                taskID: taskID,
                source: .timer,
                deviceID: "test",
                startedAt: calendar.date(byAdding: .day, value: offset, to: firstDay)!
                    .addingTimeInterval(3_600)
            )
        }
        let segments = sessions.map { session in
            TimeSegment(
                sessionID: session.id,
                taskID: taskID,
                source: .timer,
                deviceID: "test",
                startedAt: session.startedAt,
                endedAt: session.startedAt.addingTimeInterval(60)
            )
        }
        let repository = LedgerRefreshSpyRepository()
        repository.fullSegments = segments
        repository.fullSessions = sessions
        var store = LedgerStore()
        try store.refreshHistory(repository: repository, now: liveNow, calendar: calendar)

        let selectedDay = try #require(
            calendar.dateInterval(of: .day, for: sessions[10].startedAt)
        )
        let selectedIDs = store.segmentCandidateIDs(
            overlapping: selectedDay,
            evaluatedAt: selectedDay.end,
            clockReference: liveNow
        )
        let rewindIDs = store.segmentCandidateIDs(
            overlapping: selectedDay,
            evaluatedAt: selectedDay.end,
            clockReference: liveNow.addingTimeInterval(-1)
        )

        #expect(selectedIDs == [segments[10].id])
        #expect(rewindIDs.count == segments.count)
        #expect(store.segments(
            overlapping: selectedDay,
            evaluatedAt: selectedDay.end,
            clockReference: liveNow
        ).map(\.id) == [segments[10].id])
    }

    @Test @MainActor
    func indexedQueriesHandleFutureEndedRowsAndBackwardClockCorrections() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let reference = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let taskID = UUID()
        let session = TimeSession(
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: reference.addingTimeInterval(300)
        )
        let futureSegment = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: reference.addingTimeInterval(300),
            endedAt: reference.addingTimeInterval(900)
        )
        let repository = LedgerRefreshSpyRepository()
        repository.fullSegments = [futureSegment]
        repository.fullSessions = [session]
        let queryInterval = DateInterval(
            start: reference,
            end: reference.addingTimeInterval(1_200)
        )
        var store = LedgerStore()

        try store.refreshHistory(
            repository: repository,
            now: reference,
            calendar: calendar
        )
        #expect(store.segments(overlapping: queryInterval, now: reference).isEmpty)
        #expect(store.segments(
            overlapping: queryInterval,
            now: reference.addingTimeInterval(600)
        ).map(\.id) == [futureSegment.id])

        try store.refreshHistory(
            repository: repository,
            now: reference.addingTimeInterval(1_200),
            calendar: calendar
        )
        repository.rangeSegments = []
        try store.refreshVisible(repository: repository, now: reference, calendar: calendar)
        #expect(store.segment(for: futureSegment.id) != nil)
        #expect(store.segments(
            overlapping: queryInterval,
            now: reference.addingTimeInterval(600)
        ).map(\.id) == [futureSegment.id])
    }

    @Test @MainActor
    func visibleRefreshClosesAPreviouslyActiveSegmentOutsideToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let firstDay = Date(timeIntervalSince1970: 172_800)
        let secondDay = firstDay.addingTimeInterval(86_400)
        let taskID = UUID()
        let session = TimeSession(
            taskID: taskID,
            source: .pomodoro,
            deviceID: "test",
            startedAt: firstDay.addingTimeInterval(23 * 3_600)
        )
        let active = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .pomodoro,
            deviceID: "test",
            startedAt: session.startedAt
        )
        let closed = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .pomodoro,
            deviceID: "test",
            startedAt: session.startedAt,
            endedAt: session.startedAt.addingTimeInterval(60)
        )
        closed.id = active.id
        session.endedAt = closed.endedAt

        let repository = LedgerRefreshSpyRepository()
        repository.fullSegments = [active]
        repository.fullSessions = [session]
        var store = LedgerStore()
        try store.refreshHistory(
            repository: repository,
            now: secondDay.addingTimeInterval(5 * 60),
            calendar: calendar
        )

        repository.resetCounters()
        repository.segmentsByID = [closed.id: closed]
        repository.sessionsByID = [session.id: session]
        try store.refreshVisible(
            repository: repository,
            now: secondDay.addingTimeInterval(10 * 60),
            calendar: calendar
        )

        #expect(store.activeSegments.isEmpty)
        #expect(store.segment(for: active.id)?.endedAt == closed.endedAt)
        #expect(store.allSegments.map(\.id) == [active.id])
        #expect(repository.segmentsByIDsCallCount == 1)
        #expect(repository.allSegmentsCallCount == 0)
    }

    @Test @MainActor
    func recentTaskIndexIsBoundedDeterministicAndRefillsAfterRemoval() throws {
        let taskID = UUID()
        let otherTaskID = UUID()
        let base = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let sessions = (0..<14).map { index in
            TimeSession(
                taskID: index.isMultiple(of: 3) ? otherTaskID : taskID,
                source: .timer,
                deviceID: "test",
                startedAt: base.addingTimeInterval(Double(index * 60))
            )
        }
        let segments = sessions.map { session in
            TimeSegment(
                sessionID: session.id,
                taskID: session.taskID,
                source: .timer,
                deviceID: "test",
                startedAt: session.startedAt,
                endedAt: session.startedAt.addingTimeInterval(30)
            )
        }
        let repository = LedgerRefreshSpyRepository()
        repository.fullSegments = segments
        repository.fullSessions = sessions
        var store = LedgerStore()

        try store.refreshHistory(repository: repository, now: base.addingTimeInterval(1_000))

        #expect(store.recentSegmentIDsByTaskID[taskID]?.count == 8)
        let expected = segments
            .filter { $0.taskID == taskID || $0.taskID == otherTaskID }
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(4)
            .map(\.id)
        #expect(store.recentSegments(forTaskIDs: [taskID, otherTaskID], limit: 4).map(\.id) == expected)

        let removed = try #require(store.recentSegments(forTaskIDs: [taskID], limit: 8).first)
        store.replaceSegments(
            ids: [removed.id],
            with: [],
            now: base.addingTimeInterval(1_100),
            calendar: .current,
            refreshUnchangedTimeSensitiveSegments: false
        )

        let remainingTaskSegments = segments
            .filter { $0.taskID == taskID && $0.id != removed.id }
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt { return lhs.startedAt > rhs.startedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(8)
            .map(\.id)
        #expect(store.recentSegments(forTaskIDs: [taskID], limit: 8).map(\.id) == remainingTaskSegments)
    }

    @Test @MainActor
    func taskScopedRangeQueryIntersectsDateAndTaskIndexes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let day = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 17
        )))
        let interval = try #require(calendar.dateInterval(of: .day, for: day))
        let sparseTaskID = UUID()
        let deepHistoryTaskID = UUID()
        let unrelatedTaskID = UUID()

        func segment(taskID: UUID, startedAt: Date) -> (TimeSession, TimeSegment) {
            let session = TimeSession(
                taskID: taskID,
                source: .timer,
                deviceID: "test",
                startedAt: startedAt
            )
            return (
                session,
                TimeSegment(
                    sessionID: session.id,
                    taskID: taskID,
                    source: .timer,
                    deviceID: "test",
                    startedAt: startedAt,
                    endedAt: startedAt.addingTimeInterval(60)
                )
            )
        }

        let sparseCurrent = segment(
            taskID: sparseTaskID,
            startedAt: day.addingTimeInterval(3_600)
        )
        let deepCurrent = segment(
            taskID: deepHistoryTaskID,
            startedAt: day.addingTimeInterval(7_200)
        )
        let unrelated = (0..<50).map { index in
            segment(
                taskID: unrelatedTaskID,
                startedAt: day.addingTimeInterval(Double(10_800 + index * 60))
            )
        }
        let sparseHistory = (1...20).map { offset in
            segment(
                taskID: sparseTaskID,
                startedAt: day.addingTimeInterval(Double(-offset * 86_400))
            )
        }
        let deepHistory = (1...60).map { offset in
            segment(
                taskID: deepHistoryTaskID,
                startedAt: day.addingTimeInterval(Double(-offset * 86_400))
            )
        }
        let records = [sparseCurrent, deepCurrent] + unrelated + sparseHistory + deepHistory
        let repository = LedgerRefreshSpyRepository()
        repository.fullSessions = records.map { $0.0 }
        repository.fullSegments = records.map { $0.1 }
        var store = LedgerStore()
        try store.refreshHistory(repository: repository, now: interval.end, calendar: calendar)

        #expect(store.taskScopedSegmentIDs(
            overlapping: interval,
            taskIDs: [sparseTaskID],
            evaluatedAt: interval.end,
            clockReference: interval.end
        ) == [sparseCurrent.1.id])
        #expect(store.segments(
            overlapping: interval,
            taskIDs: [deepHistoryTaskID],
            evaluatedAt: interval.end,
            clockReference: interval.end
        ).map(\.id) == [deepCurrent.1.id])
    }
}

private final class LedgerRefreshSpyRepository: TimeTrackingRepository {
    var activeSegmentsCallCount = 0
    var rangeSegmentsCallCount = 0
    var allSegmentsCallCount = 0
    var sessionsCallCount = 0
    var sessionsByIDsCallCount = 0
    var segmentsByIDsCallCount = 0

    var fullSegments: [TimeSegment] = []
    var fullSessions: [TimeSession] = []
    var rangeSegments: [TimeSegment] = []
    var sessionsByID: [UUID: TimeSession] = [:]
    var segmentsByID: [UUID: TimeSegment] = [:]

    func resetCounters() {
        activeSegmentsCallCount = 0
        rangeSegmentsCallCount = 0
        allSegmentsCallCount = 0
        sessionsCallCount = 0
        sessionsByIDsCallCount = 0
        segmentsByIDsCallCount = 0
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

    func segments(ids: Set<UUID>) throws -> [TimeSegment] {
        segmentsByIDsCallCount += 1
        return ids.compactMap { segmentsByID[$0] }
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
