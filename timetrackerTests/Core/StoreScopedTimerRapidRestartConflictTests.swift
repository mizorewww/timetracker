import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedTimerRapidRestartConflictTests {
    @Test
    func concurrentReplicaRestartsCollapseToOneLWWIdentity() throws {
        let fixture = try stoppedTimerFixture(
            title: "Concurrent replicas",
            base: Date(timeIntervalSinceReferenceDate: 11_000_000)
        )
        let baseline = try SyncDataSnapshot.capture(
            context: ModelContext(fixture.container)
        )
        let left = try makeTestContext()
        let right = try makeTestContext()
        try baseline.restoreAsLocalWinner(
            context: left,
            now: fixture.stoppedAt
        )
        try baseline.restoreAsLocalWinner(
            context: right,
            now: fixture.stoppedAt
        )

        let leftOutcome = try coordinator(
            left.container,
            now: fixture.restartedAt,
            deviceID: "left"
        ).start(taskID: fixture.task.id)
        let rightOutcome = try coordinator(
            right.container,
            now: fixture.restartedAt,
            deviceID: "right"
        ).start(taskID: fixture.task.id)
        let replacementID = try #require(leftOutcome.subjectSegmentID)
        #expect(rightOutcome.subjectSegmentID == replacementID)
        #expect(
            replacementID == TimerRapidRestartPolicy().replacementSegmentID(
                predecessorSegmentID: fixture.segment.id
            )
        )

        let leftSnapshot = try SyncDataSnapshot.capture(context: left)
        let rightSnapshot = try SyncDataSnapshot.capture(context: right)
        let merged = try makeTestContext()
        try leftSnapshot.restoreAsLocalWinner(
            context: merged,
            now: fixture.restartedAt
        )
        insertPhysicalLedgerReplica(
            rightSnapshot,
            into: merged,
            deviceID: "right-cloud"
        )
        try merged.save()

        let rawSegments = try merged.fetch(FetchDescriptor<TimeSegment>())
        #expect(rawSegments.filter { $0.id == replacementID }.count == 2)
        let mergedRepository = repository(
            ModelContext(merged.container),
            now: fixture.restartedAt
        )
        #expect(try mergedRepository.activeSegments().map(\.id) == [
            replacementID,
        ])
        #expect(try mergedRepository.allSegments().map(\.id) == [
            replacementID,
        ])

        let stoppedAt = fixture.restartedAt.addingTimeInterval(10)
        let stopOutcome = try coordinator(
            merged.container,
            now: stoppedAt,
            deviceID: "stop"
        ).stop(taskID: fixture.task.id)
        #expect(stopOutcome.subjectSegmentID == replacementID)
        let stoppedRepository = repository(
            ModelContext(merged.container),
            now: stoppedAt
        )
        #expect(try stoppedRepository.activeSegments().isEmpty)
        #expect(
            try stoppedRepository.allSegments().first?.endedAt == stoppedAt
        )
    }

    @Test
    func existingDerivedIdentityFallsBackWithoutOverwritingItsTombstone() throws {
        let fixture = try stoppedTimerFixture(
            title: "Existing derived identity",
            base: Date(timeIntervalSinceReferenceDate: 12_000_000)
        )
        let derivedID = TimerRapidRestartPolicy().replacementSegmentID(
            predecessorSegmentID: fixture.segment.id
        )
        let collisionDate = fixture.stoppedAt.addingTimeInterval(1)
        let existing = TimeSegment(
            sessionID: UUID(),
            taskID: fixture.task.id,
            source: .timer,
            deviceID: "cloud",
            startedAt: fixture.segment.startedAt,
            endedAt: fixture.stoppedAt
        )
        existing.id = derivedID
        existing.deletedAt = collisionDate
        existing.updatedAt = collisionDate
        fixture.context.insert(existing)
        try fixture.context.save()

        let outcome = try coordinator(
            fixture.container,
            now: fixture.restartedAt,
            deviceID: "restart"
        ).start(taskID: fixture.task.id)

        let newID = try #require(outcome.subjectSegmentID)
        #expect(newID != derivedID)
        #expect(outcome.tombstonedSegments.isEmpty)
        let rawSegments = try ModelContext(fixture.container)
            .fetch(FetchDescriptor<TimeSegment>())
        let existingWinner = try #require(
            rawSegments.deduplicatedByID().first { $0.id == derivedID }
        )
        #expect(existingWinner.deletedAt == collisionDate)
        let repository = timeRepository(
            fixture.container,
            now: fixture.restartedAt
        )
        #expect(try repository.activeSegments().map(\.id) == [newID])
        #expect(try Set(repository.allSegments().map(\.id)) == [
            fixture.segment.id,
            newID,
        ])
    }

    @Test
    func canonicalPomodoroWinnerMovedToAnotherSessionDoesNotBlockRestart() throws {
        let fixture = try stoppedTimerFixture(
            title: "Moved Pomodoro",
            base: Date(timeIntervalSinceReferenceDate: 7_000_000)
        )
        let oldRun = PomodoroRun(
            taskID: fixture.task.id,
            deviceID: "old"
        )
        oldRun.sessionID = fixture.segment.sessionID
        oldRun.endedAt = fixture.stoppedAt
        oldRun.updatedAt = fixture.stoppedAt
        let movedWinner = PomodoroRun(
            taskID: fixture.task.id,
            deviceID: "new"
        )
        movedWinner.id = oldRun.id
        movedWinner.sessionID = UUID()
        movedWinner.endedAt = fixture.stoppedAt
        movedWinner.updatedAt = fixture.stoppedAt.addingTimeInterval(1)
        fixture.context.insert(oldRun)
        fixture.context.insert(movedWinner)
        try fixture.context.save()

        let outcome = try coordinator(
            fixture.container,
            now: fixture.restartedAt
        ).start(taskID: fixture.task.id)

        #expect(outcome.tombstonedSegments.map(\.segmentID) == [
            fixture.segment.id,
        ])
        #expect(
            try timeRepository(fixture.container, now: fixture.restartedAt)
                .activeSegments()
                .first?
                .sessionID == fixture.segment.sessionID
        )
    }

    @Test
    func canonicalPomodoroTombstoneDoesNotBlockRestart() throws {
        let fixture = try stoppedTimerFixture(
            title: "Deleted Pomodoro",
            base: Date(timeIntervalSinceReferenceDate: 8_000_000)
        )
        let oldRun = PomodoroRun(
            taskID: fixture.task.id,
            deviceID: "old"
        )
        oldRun.sessionID = fixture.segment.sessionID
        oldRun.endedAt = fixture.stoppedAt
        oldRun.updatedAt = fixture.stoppedAt
        let tombstone = PomodoroRun(
            taskID: fixture.task.id,
            deviceID: "new"
        )
        tombstone.id = oldRun.id
        tombstone.sessionID = fixture.segment.sessionID
        tombstone.endedAt = fixture.stoppedAt
        tombstone.deletedAt = fixture.stoppedAt.addingTimeInterval(1)
        tombstone.updatedAt = fixture.stoppedAt.addingTimeInterval(1)
        fixture.context.insert(oldRun)
        fixture.context.insert(tombstone)
        try fixture.context.save()

        let outcome = try coordinator(
            fixture.container,
            now: fixture.restartedAt
        ).start(taskID: fixture.task.id)

        #expect(outcome.tombstonedSegments.map(\.segmentID) == [
            fixture.segment.id,
        ])
    }

    @Test
    func restartStrictlyWinsFutureDatedSessionAndSegmentDuplicates() throws {
        let fixture = try stoppedTimerFixture(
            title: "Future duplicate",
            base: Date(timeIntervalSinceReferenceDate: 9_000_000)
        )
        let futureDate = fixture.restartedAt.addingTimeInterval(3600)
        insertClosedSessionDuplicate(
            into: fixture.context,
            original: fixture.session,
            endedAt: fixture.stoppedAt,
            updatedAt: futureDate,
            deviceID: "future-session"
        )
        insertVisibleSegmentDuplicate(
            into: fixture.context,
            original: fixture.segment,
            endedAt: fixture.stoppedAt,
            updatedAt: futureDate,
            deviceID: "future-segment"
        )
        try fixture.context.save()

        let outcome = try coordinator(
            fixture.container,
            now: fixture.restartedAt,
            deviceID: "restart"
        ).start(taskID: fixture.task.id)

        let replacementID = try #require(outcome.subjectSegmentID)
        let rawContext = ModelContext(fixture.container)
        let canonicalSegments = try rawContext
            .fetch(FetchDescriptor<TimeSegment>())
            .deduplicatedByID()
        let predecessor = try #require(canonicalSegments.first {
            $0.id == fixture.segment.id
        })
        let replacement = try #require(canonicalSegments.first {
            $0.id == replacementID
        })
        let canonicalSession = try #require(
            try rawContext.fetch(FetchDescriptor<TimeSession>())
                .deduplicatedByID()
                .first { $0.id == fixture.session.id }
        )
        #expect(predecessor.deletedAt != nil)
        #expect(predecessor.updatedAt > futureDate)
        #expect(replacement.updatedAt > futureDate)
        #expect(canonicalSession.endedAt == nil)
        #expect(canonicalSession.updatedAt > futureDate)
        #expect(
            try timeRepository(fixture.container, now: fixture.restartedAt)
                .allSegments()
                .map(\.id) == [replacementID]
        )
    }

    @Test
    func stopAfterFutureDatedRestartSurvivesActiveCloudRedelivery() throws {
        let fixture = try stoppedTimerFixture(
            title: "Future stop",
            base: Date(timeIntervalSinceReferenceDate: 9_500_000)
        )
        let futureDate = fixture.restartedAt.addingTimeInterval(3600)
        insertClosedSessionDuplicate(
            into: fixture.context,
            original: fixture.session,
            endedAt: fixture.stoppedAt,
            updatedAt: futureDate,
            deviceID: "future-session"
        )
        insertVisibleSegmentDuplicate(
            into: fixture.context,
            original: fixture.segment,
            endedAt: fixture.stoppedAt,
            updatedAt: futureDate,
            deviceID: "future-segment"
        )
        try fixture.context.save()

        let restarted = try coordinator(
            fixture.container,
            now: fixture.restartedAt,
            deviceID: "restart"
        ).start(taskID: fixture.task.id)
        let replacementID = try #require(restarted.subjectSegmentID)
        var rawContext = ModelContext(fixture.container)
        var replacement = try #require(
            try rawContext.fetch(FetchDescriptor<TimeSegment>())
                .deduplicatedByID()
                .first { $0.id == replacementID }
        )
        var session = try #require(
            try rawContext.fetch(FetchDescriptor<TimeSession>())
                .deduplicatedByID()
                .first { $0.id == fixture.session.id }
        )
        let activeSegmentVersion = replacement.updatedAt
        let openSessionVersion = session.updatedAt
        let stoppedAgainAt = fixture.restartedAt.addingTimeInterval(10)

        _ = try coordinator(
            fixture.container,
            now: stoppedAgainAt,
            deviceID: "stop"
        ).stop(segmentID: replacementID)

        rawContext = ModelContext(fixture.container)
        replacement = try #require(
            try rawContext.fetch(FetchDescriptor<TimeSegment>())
                .deduplicatedByID()
                .first { $0.id == replacementID }
        )
        session = try #require(
            try rawContext.fetch(FetchDescriptor<TimeSession>())
                .deduplicatedByID()
                .first { $0.id == fixture.session.id }
        )
        #expect(replacement.endedAt == stoppedAgainAt)
        #expect(replacement.updatedAt > activeSegmentVersion)
        #expect(session.endedAt == stoppedAgainAt)
        #expect(session.updatedAt > openSessionVersion)

        insertOpenSessionDuplicate(
            into: rawContext,
            original: session,
            updatedAt: openSessionVersion,
            deviceID: "redelivered-open-session"
        )
        insertActiveSegmentDuplicate(
            into: rawContext,
            original: replacement,
            updatedAt: activeSegmentVersion,
            deviceID: "redelivered-active-segment"
        )
        try rawContext.save()

        let canonicalSegments = try rawContext
            .fetch(FetchDescriptor<TimeSegment>())
            .visibleDeduplicatedByID()
        let canonicalSessions = try rawContext
            .fetch(FetchDescriptor<TimeSession>())
            .visibleDeduplicatedByID()
        #expect(
            canonicalSegments.first { $0.id == replacementID }?.endedAt
                == stoppedAgainAt
        )
        #expect(
            canonicalSessions.first { $0.id == fixture.session.id }?.endedAt
                == stoppedAgainAt
        )
        #expect(
            try timeRepository(fixture.container, now: stoppedAgainAt)
                .activeSegments()
                .contains { $0.id == replacementID } == false
        )
    }

    @Test
    func snapshotRestoreKeepsRestartAheadOfFutureCloudRedelivery() throws {
        let fixture = try stoppedTimerFixture(
            title: "Restore winner",
            base: Date(timeIntervalSinceReferenceDate: 10_000_000)
        )
        let outcome = try coordinator(
            fixture.container,
            now: fixture.restartedAt
        ).start(taskID: fixture.task.id)
        let replacementID = try #require(outcome.subjectSegmentID)
        let snapshot = try SyncDataSnapshot.capture(
            context: ModelContext(fixture.container)
        )

        let target = try makeTestContext()
        let restoreDate = fixture.restartedAt.addingTimeInterval(100)
        let futureDate = restoreDate.addingTimeInterval(500)
        insertClosedSessionDuplicate(
            into: target,
            original: fixture.session,
            endedAt: fixture.stoppedAt,
            updatedAt: futureDate,
            deviceID: "future-session"
        )
        insertVisibleSegmentDuplicate(
            into: target,
            original: fixture.segment,
            endedAt: fixture.stoppedAt,
            updatedAt: futureDate,
            deviceID: "future-segment"
        )
        try target.save()

        try snapshot.restoreAsLocalWinner(context: target, now: restoreDate)
        var targetSegments = try target.fetch(FetchDescriptor<TimeSegment>())
        var targetSessions = try target.fetch(FetchDescriptor<TimeSession>())
        let restoredPredecessor = try #require(
            targetSegments.deduplicatedByID().first {
                $0.id == fixture.segment.id
            }
        )
        let restoredSession = try #require(
            targetSessions.deduplicatedByID().first {
                $0.id == fixture.session.id
            }
        )
        #expect(restoredPredecessor.deletedAt != nil)
        #expect(restoredPredecessor.updatedAt > futureDate)
        #expect(restoredSession.endedAt == nil)
        #expect(restoredSession.updatedAt > futureDate)

        insertClosedSessionDuplicate(
            into: target,
            original: fixture.session,
            endedAt: fixture.stoppedAt,
            updatedAt: futureDate,
            deviceID: "redelivered-session"
        )
        insertVisibleSegmentDuplicate(
            into: target,
            original: fixture.segment,
            endedAt: fixture.stoppedAt,
            updatedAt: futureDate,
            deviceID: "redelivered-segment"
        )
        try target.save()

        targetSegments = try target.fetch(FetchDescriptor<TimeSegment>())
        targetSessions = try target.fetch(FetchDescriptor<TimeSession>())
        #expect(
            targetSegments.deduplicatedByID().first {
                $0.id == fixture.segment.id
            }?.deletedAt != nil
        )
        #expect(
            targetSessions.deduplicatedByID().first {
                $0.id == fixture.session.id
            }?.endedAt == nil
        )
        let restoredSnapshot = try SyncDataSnapshot.capture(context: target)
        #expect(
            restoredSnapshot.segments.first {
                $0.id == fixture.segment.id
            }?.deletedAt != nil
        )
        #expect(
            restoredSnapshot.segments.first {
                $0.id == replacementID
            }?.deletedAt == nil
        )
        #expect(
            restoredSnapshot.sessions.first {
                $0.id == fixture.session.id
            }?.endedAt == nil
        )
    }

    @Test
    func crossMidnightRestartInvalidatesLoadedHistory() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let midnight = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 19
        )))
        let startedAt = midnight.addingTimeInterval(-90)
        let stoppedAt = midnight.addingTimeInterval(-20)
        let restartedAt = midnight.addingTimeInterval(10)
        let context = try makeTestContext()
        let task = try makeTask("Midnight", context: context)
        let first = try repository(context, now: startedAt)
            .startTask(taskID: task.id, source: .timer)
        try repository(ModelContext(context.container), now: stoppedAt)
            .stopSegment(segmentID: first.id)

        var ledger = LedgerStore()
        try ledger.refresh(
            repository: timeRepository(context.container, now: stoppedAt),
            now: stoppedAt,
            calendar: calendar
        )
        #expect(ledger.allSegments.map(\.id) == [first.id])

        let outcome = try coordinator(
            context.container,
            now: restartedAt
        ).start(taskID: task.id)
        let replacementID = try #require(outcome.subjectSegmentID)
        let expectedRange = StoreInvalidationRange(
            start: startedAt,
            end: stoppedAt
        )
        #expect(outcome.events.contains(.ledgerChanged(
            taskID: task.id,
            dateInterval: expectedRange,
            isVisible: false
        )))
        let plan = StoreRefreshPlanner().plan(after: outcome.events)
        #expect(plan.scopes.contains(.ledgerVisible))
        #expect(plan.scopes.contains(.ledgerHistory))
        #expect(plan.affectedLedgerRanges == [expectedRange])

        let freshRepository = timeRepository(
            context.container,
            now: restartedAt
        )
        try ledger.refreshVisible(
            repository: freshRepository,
            now: restartedAt,
            calendar: calendar
        )
        #expect(Set(ledger.allSegments.map(\.id)) == [first.id, replacementID])
        try ledger.refreshHistoryRanges(
            repository: freshRepository,
            ranges: plan.affectedLedgerRanges,
            now: restartedAt
        )
        #expect(ledger.allSegments.map(\.id) == [replacementID])
        let changes = Dictionary(
            uniqueKeysWithValues: ledger.rollupChanges.map { ($0.id, $0) }
        )
        #expect(changes[first.id]?.before != nil)
        #expect(changes[first.id]?.after == nil)
        #expect(changes[replacementID]?.before == nil)
        #expect(changes[replacementID]?.after != nil)
    }

    private struct StoppedTimerFixture {
        let context: ModelContext
        let container: ModelContainer
        let task: TaskNode
        let session: TimeSession
        let segment: TimeSegment
        let stoppedAt: Date
        let restartedAt: Date
    }

    private func stoppedTimerFixture(
        title: String,
        base: Date
    ) throws -> StoppedTimerFixture {
        let context = try makeTestContext()
        let task = try makeTask(title, context: context)
        let startedAt = base
        let stoppedAt = startedAt.addingTimeInterval(120)
        let segment = try repository(context, now: startedAt)
            .startTask(taskID: task.id, source: .timer)
        try repository(ModelContext(context.container), now: stoppedAt)
            .stopSegment(segmentID: segment.id)
        let session = try #require(
            try timeRepository(context.container, now: stoppedAt)
                .sessions(ids: [segment.sessionID])
                .first
        )
        return StoppedTimerFixture(
            context: context,
            container: context.container,
            task: task,
            session: session,
            segment: segment,
            stoppedAt: stoppedAt,
            restartedAt: stoppedAt.addingTimeInterval(30)
        )
    }

    private func makeTask(
        _ title: String,
        context: ModelContext
    ) throws -> TaskNode {
        try SwiftDataTaskRepository(context: context, deviceID: "fixture")
            .createTask(
                title: title,
                parentID: nil,
                colorHex: nil,
                iconName: nil
            )
    }

    private func repository(
        _ context: ModelContext,
        now: Date
    ) -> SwiftDataTimeTrackingRepository {
        SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "fixture",
            nowProvider: { now }
        )
    }

    private func timeRepository(
        _ container: ModelContainer,
        now: Date
    ) -> SwiftDataTimeTrackingRepository {
        repository(ModelContext(container), now: now)
    }

    private func coordinator(
        _ container: ModelContainer,
        now: Date,
        deviceID: String = "fixture"
    ) -> StoreScopedTimerCommandCoordinator {
        StoreScopedTimerCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: deviceID,
            nowProvider: { now }
        )
    }

    private func insertPhysicalLedgerReplica(
        _ snapshot: SyncDataSnapshot,
        into context: ModelContext,
        deviceID: String
    ) {
        for record in snapshot.sessions {
            let session = TimeSession(
                taskID: record.taskID,
                source: TimeSessionSource(rawValue: record.sourceRaw) ?? .timer,
                deviceID: deviceID,
                startedAt: record.startedAt,
                titleSnapshot: record.titleSnapshot
            )
            session.id = record.id
            session.endedAt = record.endedAt
            session.note = record.note
            session.createdAt = record.createdAt
            session.updatedAt = record.updatedAt
            session.deletedAt = record.deletedAt
            context.insert(session)
        }
        for record in snapshot.segments {
            let segment = TimeSegment(
                sessionID: record.sessionID,
                taskID: record.taskID,
                source: TimeSessionSource(rawValue: record.sourceRaw) ?? .timer,
                deviceID: deviceID,
                startedAt: record.startedAt,
                endedAt: record.endedAt
            )
            segment.id = record.id
            segment.createdAt = record.createdAt
            segment.updatedAt = record.updatedAt
            segment.deletedAt = record.deletedAt
            context.insert(segment)
        }
    }

    private func insertClosedSessionDuplicate(
        into context: ModelContext,
        original: TimeSession,
        endedAt: Date,
        updatedAt: Date,
        deviceID: String
    ) {
        let duplicate = TimeSession(
            taskID: original.taskID,
            source: TimeSessionSource(rawValue: original.sourceRaw) ?? .timer,
            deviceID: deviceID,
            startedAt: original.startedAt,
            titleSnapshot: original.titleSnapshot
        )
        duplicate.id = original.id
        duplicate.endedAt = endedAt
        duplicate.note = original.note
        duplicate.createdAt = original.createdAt
        duplicate.updatedAt = updatedAt
        context.insert(duplicate)
    }

    private func insertVisibleSegmentDuplicate(
        into context: ModelContext,
        original: TimeSegment,
        endedAt: Date,
        updatedAt: Date,
        deviceID: String
    ) {
        let duplicate = TimeSegment(
            sessionID: original.sessionID,
            taskID: original.taskID,
            source: TimeSessionSource(rawValue: original.sourceRaw) ?? .timer,
            deviceID: deviceID,
            startedAt: original.startedAt,
            endedAt: endedAt
        )
        duplicate.id = original.id
        duplicate.createdAt = original.createdAt
        duplicate.updatedAt = updatedAt
        context.insert(duplicate)
    }

    private func insertOpenSessionDuplicate(
        into context: ModelContext,
        original: TimeSession,
        updatedAt: Date,
        deviceID: String
    ) {
        let duplicate = TimeSession(
            taskID: original.taskID,
            source: TimeSessionSource(rawValue: original.sourceRaw) ?? .timer,
            deviceID: deviceID,
            startedAt: original.startedAt,
            titleSnapshot: original.titleSnapshot
        )
        duplicate.id = original.id
        duplicate.note = original.note
        duplicate.createdAt = original.createdAt
        duplicate.updatedAt = updatedAt
        context.insert(duplicate)
    }

    private func insertActiveSegmentDuplicate(
        into context: ModelContext,
        original: TimeSegment,
        updatedAt: Date,
        deviceID: String
    ) {
        let duplicate = TimeSegment(
            sessionID: original.sessionID,
            taskID: original.taskID,
            source: TimeSessionSource(rawValue: original.sourceRaw) ?? .timer,
            deviceID: deviceID,
            startedAt: original.startedAt
        )
        duplicate.id = original.id
        duplicate.createdAt = original.createdAt
        duplicate.updatedAt = updatedAt
        context.insert(duplicate)
    }
}
