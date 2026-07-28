import Foundation
import SwiftData

@MainActor
struct StoreScopedSegmentCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String?
    let nowProvider: () -> Date

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
        self.nowProvider = nowProvider
    }

    func addManualTime(
        draft: ManualTimeDraft,
        taskID: UUID
    ) throws {
        try withLockedFreshContext { _, now, timeRepository, _ in
            _ = try LedgerCommandHandler(
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            ).addManualTime(
                draft: draft,
                taskID: taskID,
                repository: timeRepository
            )
        }
    }

    func update(
        draft: SegmentEditorDraft,
        taskID: UUID
    ) throws -> StoreScopedSegmentMutationOutcome {
        try withLockedFreshContext { context, now, timeRepository, pomodoroRepository in
            let canonical = try requiredCanonicalState(
                baseline: draft.baseline,
                timeRepository: timeRepository,
                pomodoroRepository: pomodoroRepository
            )
            try validateUpdate(
                draft: draft,
                taskID: taskID,
                canonicalSegment: canonical.segment,
                now: now,
                context: context
            )
            let allowParallelTimers = try TimerAdmissionPreferenceResolver
                .allowParallelTimers(in: context)
            let activeSegments = try timeRepository.activeSegments()
            let sessionSiblingStops = activeSegments.filter { segment in
                segment.id != canonical.segment.id &&
                    segment.sessionID == canonical.segment.sessionID &&
                    draft.wasActive
            }
            let admissionStops = activeSegments.filter { segment in
                segment.id != canonical.segment.id &&
                    segment.sessionID != canonical.segment.sessionID &&
                    draft.isActive &&
                    (segment.taskID == taskID || allowParallelTimers == false)
            }
            let activeRuns = try pomodoroRepository.activeRuns()
            let impactedSessionIDs = Set(
                [canonical.segment.sessionID] +
                    sessionSiblingStops.map(\.sessionID) +
                    admissionStops.map(\.sessionID)
            )
            let runBySessionID = try validatedRunBySessionID(
                activeRuns: activeRuns,
                sessionIDs: impactedSessionIDs
            )
            let before = try mutationState(
                sessionIDs: impactedSessionIDs,
                activeRuns: activeRuns,
                timeRepository: timeRepository
            )
            for segment in sessionSiblingStops {
                try timeRepository.stopSegment(segmentID: segment.id)
            }
            let timerHandler = TimerCommandHandler(
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            )
            for segment in admissionStops {
                try timerHandler.stop(
                    segment: segment,
                    pomodoroRuns: runBySessionID[segment.sessionID].map { [$0] } ?? [],
                    timeRepository: timeRepository,
                    context: context
                )
            }

            try LedgerCommandHandler(
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            ).updateSegment(
                draft: draft,
                taskID: taskID,
                activePomodoroSessionID: canonical.linkedRun.map { _ in
                    canonical.segment.sessionID
                },
                pomodoroRuns: canonical.linkedRun.map { [$0] } ?? [],
                repository: timeRepository,
                context: context
            )
            return try outcome(
                subjectSegmentID: draft.segmentID,
                before: before,
                referenceDate: now,
                timeRepository: timeRepository,
                pomodoroRepository: pomodoroRepository
            )
        }
    }

    func delete(
        segmentID: UUID,
        expectedBaseline: SegmentEditorDraftBaseline?
    ) throws -> StoreScopedSegmentMutationOutcome {
        try withLockedFreshContext { context, now, timeRepository, pomodoroRepository in
            let canonical = try requiredCanonicalState(
                segmentID: segmentID,
                expectedBaseline: expectedBaseline,
                timeRepository: timeRepository,
                pomodoroRepository: pomodoroRepository
            )
            let before = try mutationState(
                sessionIDs: [canonical.segment.sessionID],
                activeRuns: pomodoroRepository.activeRuns(),
                timeRepository: timeRepository
            )
            try LedgerCommandHandler(
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            ).softDeleteSegment(
                segmentID,
                activePomodoroSessionID: canonical.linkedRun.map { _ in
                    canonical.segment.sessionID
                },
                pomodoroRuns: canonical.linkedRun.map { [$0] } ?? [],
                repository: timeRepository,
                context: context
            )
            return try outcome(
                subjectSegmentID: segmentID,
                before: before,
                referenceDate: now,
                timeRepository: timeRepository,
                pomodoroRepository: pomodoroRepository
            )
        }
    }

    var resolvedDeviceID: String {
        deviceID ?? DeviceIdentity.current
    }

    private func withLockedFreshContext<Result>(
        _ operation: (
            ModelContext,
            Date,
            SwiftDataTimeTrackingRepository,
            SwiftDataPomodoroRepository
        ) throws -> Result
    ) throws -> Result {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )
        return try transaction.withFreshContext(author: .localMutation) { context in
            let now = nowProvider()
            let timeRepository = SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            )
            let pomodoroRepository = SwiftDataPomodoroRepository(
                context: context,
                timeRepository: timeRepository,
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            )
            return try operation(context, now, timeRepository, pomodoroRepository)
        }
    }
}
