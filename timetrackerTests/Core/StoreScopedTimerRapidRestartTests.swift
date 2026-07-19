import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedTimerRapidRestartTests {
    @Test
    func restartWithinOneMinuteCreatesANewStopIdentityAndContinuesTheSession() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask("Continuous work", context: context)
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let stoppedAt = startedAt.addingTimeInterval(120)
        let restartedAt = stoppedAt.addingTimeInterval(30)
        let first = try repository(
            context,
            now: startedAt,
            deviceID: "first-device"
        ).startTask(taskID: task.id, source: .timer)
        let originalSession = try #require(
            try repository(context, now: startedAt)
                .sessions(ids: [first.sessionID])
                .first
        )
        originalSession.note = "Preserve this context"
        try context.save()
        try repository(
            ModelContext(container),
            now: stoppedAt,
            deviceID: "stop-device"
        ).stopSegment(segmentID: first.id)

        let stoppedSession = try #require(
            try repository(ModelContext(container), now: stoppedAt)
                .sessions(ids: [first.sessionID])
                .first
        )
        let stoppedMutationID = stoppedSession.clientMutationID
        let originalSessionCreatedAt = stoppedSession.createdAt
        let originalSegmentCreatedAt = first.createdAt
        let coordinator = makeCoordinator(
            container: container,
            now: restartedAt,
            deviceID: "restart-device"
        )

        let outcome = try coordinator.start(
            taskID: task.id,
            source: .watch
        )

        let replacementID = try #require(outcome.subjectSegmentID)
        #expect(replacementID != first.id)
        #expect(outcome.createdSegment?.segmentID == replacementID)
        #expect(outcome.didMutate)

        let rawContext = ModelContext(container)
        let rawSegments = try rawContext.fetch(FetchDescriptor<TimeSegment>())
        let predecessor = try #require(rawSegments.first { $0.id == first.id })
        let replacement = try #require(rawSegments.first { $0.id == replacementID })
        let session = try #require(
            try rawContext.fetch(FetchDescriptor<TimeSession>())
                .first { $0.id == first.sessionID }
        )
        #expect(rawSegments.count == 2)
        #expect(predecessor.deletedAt != nil)
        #expect(predecessor.endedAt == stoppedAt)
        #expect(predecessor.createdAt == originalSegmentCreatedAt)
        #expect(replacement.deletedAt == nil)
        #expect(replacement.endedAt == nil)
        #expect(replacement.startedAt == startedAt)
        #expect(replacement.sessionID == first.sessionID)
        #expect(replacement.source == .timer)
        #expect(replacement.deviceID == "restart-device")
        #expect(session.startedAt == startedAt)
        #expect(session.endedAt == nil)
        #expect(session.note == "Preserve this context")
        #expect(session.titleSnapshot == task.title)
        #expect(session.sourceRaw == TimeSessionSource.timer.rawValue)
        #expect(session.createdAt == originalSessionCreatedAt)
        #expect(session.clientMutationID != stoppedMutationID)
        #expect(session.deviceID == "restart-device")
        #expect(
            try repository(ModelContext(container), now: restartedAt)
                .allSegments()
                .map(\.id) == [replacementID]
        )
        let snapshot = try SyncDataSnapshot.capture(context: rawContext)
        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.sessions.first?.id == first.sessionID)
        #expect(snapshot.sessions.first?.deletedAt == nil)
        #expect(snapshot.segments.count == 2)
        #expect(
            snapshot.segments.first { $0.id == first.id }?.deletedAt != nil
        )
        #expect(
            snapshot.segments.first { $0.id == replacementID }?.deletedAt == nil
        )

        let staleStop = try makeCoordinator(
            container: container,
            now: restartedAt.addingTimeInterval(10)
        ).stop(segmentID: first.id)
        #expect(staleStop.didMutate == false)
        #expect(
            try repository(ModelContext(container), now: restartedAt)
                .activeSegments()
                .map(\.id) == [replacementID]
        )

        let finalStop = restartedAt.addingTimeInterval(20)
        let stopped = try makeCoordinator(
            container: container,
            now: finalStop
        ).stop(segmentID: replacementID)
        #expect(stopped.subjectSegmentID == replacementID)
        let finalRepository = repository(ModelContext(container), now: finalStop)
        let visible = try #require(finalRepository.allSegments().first)
        let finalSession = try #require(
            try finalRepository.sessions(ids: [first.sessionID]).first
        )
        #expect(visible.id == replacementID)
        #expect(visible.startedAt == startedAt)
        #expect(visible.endedAt == finalStop)
        #expect(finalSession.endedAt == finalStop)
    }

    @Test
    func exactOneMinuteGapCreatesAnIndependentSession() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask("Boundary", context: context)
        let startedAt = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let stoppedAt = startedAt.addingTimeInterval(120)
        let first = try repository(context, now: startedAt)
            .startTask(taskID: task.id, source: .timer)
        try repository(ModelContext(container), now: stoppedAt)
            .stopSegment(segmentID: first.id)
        let restartedAt = stoppedAt.addingTimeInterval(60)

        let outcome = try makeCoordinator(
            container: container,
            now: restartedAt
        ).start(taskID: task.id, source: .watch)

        let replacementID = try #require(outcome.subjectSegmentID)
        let rawContext = ModelContext(container)
        let segments = try rawContext.fetch(FetchDescriptor<TimeSegment>())
        let sessions = try rawContext.fetch(FetchDescriptor<TimeSession>())
        let predecessor = try #require(segments.first { $0.id == first.id })
        let replacement = try #require(segments.first { $0.id == replacementID })
        #expect(segments.count == 2)
        #expect(sessions.count == 2)
        #expect(predecessor.deletedAt == nil)
        #expect(replacement.sessionID != first.sessionID)
        #expect(replacement.startedAt == restartedAt)
        #expect(replacement.source == .watch)
    }

    @Test
    func workByAnotherTaskInsideTheGapPreventsCoalescing() throws {
        let context = try makeTestContext()
        let container = context.container
        let firstTask = try makeTask("First", context: context)
        let otherTask = try makeTask("Other", context: context)
        let startedAt = Date(timeIntervalSinceReferenceDate: 3_000_000)
        let firstStoppedAt = startedAt.addingTimeInterval(120)
        let first = try repository(context, now: startedAt)
            .startTask(taskID: firstTask.id, source: .timer)
        try repository(ModelContext(container), now: firstStoppedAt)
            .stopSegment(segmentID: first.id)

        let otherStartedAt = firstStoppedAt.addingTimeInterval(10)
        let otherStoppedAt = firstStoppedAt.addingTimeInterval(30)
        let other = try repository(
            ModelContext(container),
            now: otherStartedAt
        ).startTask(taskID: otherTask.id, source: .watch)
        try repository(ModelContext(container), now: otherStoppedAt)
            .stopSegment(segmentID: other.id)

        let restartedAt = firstStoppedAt.addingTimeInterval(40)
        let outcome = try makeCoordinator(
            container: container,
            now: restartedAt
        ).start(taskID: firstTask.id)

        let replacementID = try #require(outcome.subjectSegmentID)
        let rawContext = ModelContext(container)
        let segments = try rawContext.fetch(FetchDescriptor<TimeSegment>())
        let predecessor = try #require(segments.first { $0.id == first.id })
        let replacement = try #require(segments.first { $0.id == replacementID })
        #expect(segments.count == 3)
        #expect(predecessor.deletedAt == nil)
        #expect(replacement.sessionID != first.sessionID)
        #expect(replacement.startedAt == restartedAt)
    }

    @Test
    func repeatedShortRestartsKeepOneVisibleSegmentAndTheOriginalSession() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask("Chain", context: context)
        let startedAt = Date(timeIntervalSinceReferenceDate: 4_000_000)
        let firstStop = startedAt.addingTimeInterval(60)
        let first = try repository(context, now: startedAt)
            .startTask(taskID: task.id, source: .shortcut)
        try repository(ModelContext(container), now: firstStop)
            .stopSegment(segmentID: first.id)

        let secondStart = firstStop.addingTimeInterval(20)
        let second = try #require(
            try makeCoordinator(container: container, now: secondStart)
                .start(taskID: task.id, source: .timer)
                .subjectSegmentID
        )
        let secondStop = secondStart.addingTimeInterval(40)
        _ = try makeCoordinator(container: container, now: secondStop)
            .stop(segmentID: second)

        let thirdStart = secondStop.addingTimeInterval(20)
        let third = try #require(
            try makeCoordinator(container: container, now: thirdStart)
                .start(taskID: task.id, source: .liveActivity)
                .subjectSegmentID
        )

        let rawContext = ModelContext(container)
        let rawSegments = try rawContext.fetch(FetchDescriptor<TimeSegment>())
        let visible = rawSegments.visibleDeduplicatedByID()
        #expect(rawSegments.count == 3)
        #expect(rawSegments.filter { $0.deletedAt != nil }.count == 2)
        #expect(visible.map(\.id) == [third])
        #expect(visible.first?.sessionID == first.sessionID)
        #expect(visible.first?.startedAt == startedAt)
        #expect(visible.first?.source == .shortcut)
        #expect(
            try rawContext.fetch(FetchDescriptor<TimeSession>())
                .visibleDeduplicatedByID()
                .map(\.id) == [first.sessionID]
        )
    }

    @Test
    func aPomodoroLinkedSessionIsNeverReused() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask("Protected", context: context)
        let startedAt = Date(timeIntervalSinceReferenceDate: 5_000_000)
        let stoppedAt = startedAt.addingTimeInterval(120)
        let first = try repository(context, now: startedAt)
            .startTask(taskID: task.id, source: .timer)
        try repository(ModelContext(container), now: stoppedAt)
            .stopSegment(segmentID: first.id)
        let run = PomodoroRun(
            taskID: task.id,
            focus: 1_500,
            breakSeconds: 300,
            targetRounds: 1,
            deviceID: "fixture"
        )
        run.sessionID = first.sessionID
        run.startedAt = startedAt
        run.endedAt = stoppedAt
        run.state = .completed
        context.insert(run)
        try context.save()
        let restartedAt = stoppedAt.addingTimeInterval(30)

        let outcome = try makeCoordinator(
            container: container,
            now: restartedAt
        ).start(taskID: task.id)

        let replacementID = try #require(outcome.subjectSegmentID)
        let rawContext = ModelContext(container)
        let segments = try rawContext.fetch(FetchDescriptor<TimeSegment>())
        let predecessor = try #require(segments.first { $0.id == first.id })
        let replacement = try #require(segments.first { $0.id == replacementID })
        #expect(predecessor.deletedAt == nil)
        #expect(replacement.sessionID != first.sessionID)
        #expect(replacement.startedAt == restartedAt)
        #expect(run.deletedAt == nil)
    }

    @Test
    func replaceAllNeverCoalescesARecentlyClosedPredecessor() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask("Explicit replacement", context: context)
        let startedAt = Date(timeIntervalSinceReferenceDate: 6_000_000)
        let stoppedAt = startedAt.addingTimeInterval(120)
        let first = try repository(context, now: startedAt)
            .startTask(taskID: task.id, source: .timer)
        try repository(ModelContext(container), now: stoppedAt)
            .stopSegment(segmentID: first.id)
        let restartedAt = stoppedAt.addingTimeInterval(30)

        let outcome = try makeCoordinator(
            container: container,
            now: restartedAt
        ).start(
            taskID: task.id,
            sameTaskBehavior: .replaceAll,
            source: .watch
        )

        let replacementID = try #require(outcome.subjectSegmentID)
        let rawContext = ModelContext(container)
        let segments = try rawContext.fetch(FetchDescriptor<TimeSegment>())
        let sessions = try rawContext.fetch(FetchDescriptor<TimeSession>())
        let predecessor = try #require(segments.first { $0.id == first.id })
        let replacement = try #require(segments.first {
            $0.id == replacementID
        })
        #expect(segments.count == 2)
        #expect(sessions.count == 2)
        #expect(predecessor.deletedAt == nil)
        #expect(predecessor.endedAt == stoppedAt)
        #expect(replacement.sessionID != first.sessionID)
        #expect(replacement.startedAt == restartedAt)
        #expect(replacement.source == .watch)
        #expect(outcome.tombstonedSegments.isEmpty)
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
        now: Date,
        deviceID: String = "fixture"
    ) -> SwiftDataTimeTrackingRepository {
        SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: deviceID,
            nowProvider: { now }
        )
    }

    private func makeCoordinator(
        container: ModelContainer,
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
}
