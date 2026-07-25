import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedSegmentCommandCoordinatorTests {
    @Test
    func manualTimeAcceptsFreshLegacyCompletedTaskInsideTheStoreTransaction() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask("Manual target", context: context)
        let now = Date(timeIntervalSinceReferenceDate: 500_000)
        var draft = ManualTimeDraft(taskID: task.id, tasks: [task])
        draft.startedAt = now.addingTimeInterval(-600)
        draft.endedAt = now.addingTimeInterval(-60)

        let siblingContext = ModelContext(container)
        let siblingRepository = SwiftDataTaskRepository(
            context: siblingContext,
            deviceID: "sibling"
        )
        let siblingTask = try #require(try siblingRepository.task(id: task.id))
        siblingTask.statusRaw = LegacyTaskStatusRaw.completed
        try siblingContext.save()

        try makeStoreScopedSegmentCoordinator(
            container: container,
            now: now
        ).addManualTime(draft: draft, taskID: task.id)

        let segments = try timeRepository(
            ModelContext(container),
            now: now
        ).allSegments()
        #expect(segments.count == 1)
        #expect(
            segments.first?.taskID == task.id &&
                segments.first?.startedAt == draft.startedAt &&
                segments.first?.endedAt == draft.endedAt
        )
    }

    @Test
    func staleActiveDraftCannotReopenSegmentStoppedBySibling() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask("Active", context: context)
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let segment = try timeRepository(
            context,
            now: startedAt
        ).startTask(taskID: task.id, source: .timer)
        let staleDraft = try makeStoreScopedSegmentDraft(
            segmentID: segment.id,
            container: container
        )

        let stoppedAt = startedAt.addingTimeInterval(120)
        try timeRepository(
            ModelContext(container),
            now: stoppedAt
        ).stopSegment(segmentID: segment.id)
        let stoppedSession = try #require(
            try timeRepository(ModelContext(container), now: stoppedAt)
                .sessions(ids: [segment.sessionID])
                .first
        )
        let siblingMutationID = stoppedSession.clientMutationID

        #expect(throws: SegmentMutationError.staleDraft) {
            _ = try makeStoreScopedSegmentCoordinator(
                container: container,
                now: stoppedAt
            ).update(
                draft: staleDraft,
                taskID: task.id
            )
        }

        let freshRepository = timeRepository(ModelContext(container), now: stoppedAt)
        let persisted = try #require(
            try freshRepository.allSegments().first { $0.id == segment.id }
        )
        let session = try #require(
            try freshRepository.sessions(ids: [segment.sessionID]).first
        )
        #expect(persisted.endedAt == stoppedAt)
        #expect(try freshRepository.activeSegments().isEmpty)
        #expect(session.clientMutationID == siblingMutationID)
    }

    @Test
    func staleBaselineCannotDeleteSiblingEditedSegment() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask("Manual", context: context)
        let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let originalStart = now.addingTimeInterval(-600)
        let segment = try timeRepository(context, now: now).addManualSegment(
            taskID: task.id,
            startedAt: originalStart,
            endedAt: now.addingTimeInterval(-300),
            note: "Original"
        )
        let staleDraft = try makeStoreScopedSegmentDraft(
            segmentID: segment.id,
            container: container
        )
        let editedStart = originalStart.addingTimeInterval(60)
        let editedEnd = now.addingTimeInterval(-120)
        try timeRepository(
            ModelContext(container),
            now: now
        ).updateSegment(
            segmentID: segment.id,
            taskID: task.id,
            startedAt: editedStart,
            endedAt: editedEnd,
            note: "Sibling edit"
        )

        #expect(throws: SegmentMutationError.staleDraft) {
            _ = try makeStoreScopedSegmentCoordinator(
                container: container,
                now: now
            ).delete(
                segmentID: segment.id,
                expectedBaseline: staleDraft.baseline
            )
        }

        let repository = timeRepository(ModelContext(container), now: now)
        let persisted = try #require(
            try repository.allSegments().first { $0.id == segment.id }
        )
        let session = try #require(
            try repository.sessions(ids: [segment.sessionID]).first
        )
        #expect(persisted.deletedAt == nil)
        #expect(persisted.startedAt == editedStart)
        #expect(persisted.endedAt == editedEnd)
        #expect(session.note == "Sibling edit")
    }

    @Test
    func unavailableTargetIsRejectedBeforeExclusiveAdmissionStops() throws {
        let context = try makeTestContext()
        let container = context.container
        let subjectTask = try makeTask("Subject", context: context)
        let targetTask = try makeTask("Unavailable", context: context)
        let otherTask = try makeTask("Other", context: context)
        let startedAt = Date(timeIntervalSinceReferenceDate: 3_000_000)
        let repository = timeRepository(context, now: startedAt)
        let subject = try repository.startTask(
            taskID: subjectTask.id,
            source: .timer
        )
        let other = try repository.startTask(
            taskID: otherTask.id,
            source: .watch
        )
        var draft = try makeStoreScopedSegmentDraft(
            segmentID: subject.id,
            container: container
        )
        draft.taskID = targetTask.id
        try SwiftDataTaskRepository(
            context: ModelContext(container),
            deviceID: "sibling"
        ).archiveTask(taskID: targetTask.id)

        #expect(throws: TimeTrackingRepositoryError.taskUnavailable) {
            _ = try makeStoreScopedSegmentCoordinator(
                container: container,
                now: startedAt.addingTimeInterval(60)
            ).update(
                draft: draft,
                taskID: targetTask.id
            )
        }

        let activeIDs = try Set(
            timeRepository(
                ModelContext(container),
                now: startedAt.addingTimeInterval(60)
            ).activeSegments().map(\.id)
        )
        #expect(activeIDs == [subject.id, other.id])
    }

    @Test
    func activeSegmentRebindReadsExclusiveAdmissionFromTheFreshStore() throws {
        let context = try makeTestContext()
        let container = context.container
        let sourceTask = try makeTask("Source", context: context)
        let targetTask = try makeTask("Target", context: context)
        let otherTask = try makeTask("Other", context: context)
        let startedAt = Date(timeIntervalSinceReferenceDate: 3_500_000)
        let repository = timeRepository(context, now: startedAt)
        let subject = try repository.startTask(taskID: sourceTask.id, source: .timer)
        let other = try repository.startTask(taskID: otherTask.id, source: .watch)
        var draft = try makeStoreScopedSegmentDraft(
            segmentID: subject.id,
            container: container
        )
        draft.taskID = targetTask.id
        try setTestAllowParallelTimers(false, context: context)

        _ = try makeStoreScopedSegmentCoordinator(
            container: container,
            now: startedAt.addingTimeInterval(60)
        ).update(draft: draft, taskID: targetTask.id)

        let freshRepository = timeRepository(
            ModelContext(container),
            now: startedAt.addingTimeInterval(60)
        )
        let active = try freshRepository.activeSegments()
        #expect(active.map(\.id) == [subject.id])
        #expect(active.first?.taskID == targetTask.id)
        #expect(
            try freshRepository.allSegments().first { $0.id == other.id }?.endedAt != nil
        )
    }

    @Test
    func missingDeleteDoesNotTouchExistingTimer() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask("Existing", context: context)
        let now = Date(timeIntervalSinceReferenceDate: 4_000_000)
        let segment = try timeRepository(context, now: now).startTask(
            taskID: task.id,
            source: .timer
        )

        #expect(throws: SegmentMutationError.staleDraft) {
            _ = try makeStoreScopedSegmentCoordinator(
                container: container,
                now: now.addingTimeInterval(30)
            ).delete(segmentID: UUID(), expectedBaseline: nil)
        }
        #expect(
            try timeRepository(ModelContext(container), now: now)
                .activeSegments()
                .map(\.id) == [segment.id]
        )
    }

    @Test
    func noteOnlyEditDoesNotRewriteSiblingConflictMetadata() throws {
        let context = try makeTestContext()
        let container = context.container
        let task = try makeTask("Session", context: context)
        let startedAt = Date(timeIntervalSinceReferenceDate: 4_500_000)
        let session = TimeSession(
            taskID: task.id,
            source: .manual,
            deviceID: "original",
            startedAt: startedAt,
            titleSnapshot: task.title
        )
        let subject = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .manual,
            deviceID: "original",
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60)
        )
        let sibling = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .manual,
            deviceID: "original",
            startedAt: startedAt.addingTimeInterval(120),
            endedAt: startedAt.addingTimeInterval(180)
        )
        session.endedAt = sibling.endedAt
        context.insert(session)
        context.insert(subject)
        context.insert(sibling)
        try context.save()
        let siblingUpdatedAt = sibling.updatedAt
        var draft = try makeStoreScopedSegmentDraft(
            segmentID: subject.id,
            container: container
        )
        draft.note = "Session note"

        let outcome = try makeStoreScopedSegmentCoordinator(
            container: container,
            now: startedAt.addingTimeInterval(300)
        ).update(
            draft: draft,
            taskID: task.id
        )

        let freshSibling = try #require(
            try timeRepository(ModelContext(container), now: startedAt)
                .allSegments()
                .first { $0.id == sibling.id }
        )
        #expect(freshSibling.updatedAt == siblingUpdatedAt)
        #expect(freshSibling.deviceID == "original")
        #expect(outcome.segmentChanges.map(\.before.segmentID) == [subject.id])
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

    private func timeRepository(
        _ context: ModelContext,
        now: Date
    ) -> SwiftDataTimeTrackingRepository {
        SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "fixture",
            nowProvider: { now }
        )
    }
}
