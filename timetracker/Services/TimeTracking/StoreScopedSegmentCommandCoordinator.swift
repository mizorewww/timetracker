import Foundation
import SwiftData

@MainActor
struct StoreScopedSegmentCommandCoordinator {
    let session: StoreMutationSession
    let deviceID: String?
    let nowProvider: () -> Date

    init(
        session: StoreMutationSession,
        deviceID: String? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.deviceID = deviceID
        self.nowProvider = nowProvider
    }

    func addManualTime(
        draft: ManualTimeDraft,
        taskID: UUID
    ) throws {
        try withLockedFreshContext { _, _, timeRepository, _ in
            _ = try timeRepository.addManualSegment(
                taskID: taskID,
                startedAt: draft.startedAt,
                endedAt: draft.endedAt,
                note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
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
            let pomodoroHandler = PomodoroCommandHandler(
                deviceID: resolvedDeviceID,
                nowProvider: { now }
            )
            for segment in admissionStops {
                try pomodoroHandler.stopTimerSegment(
                    segment,
                    pomodoroRuns: runBySessionID[segment.sessionID].map { [$0] } ?? [],
                    timeRepository: timeRepository,
                    context: context
                )
            }

            guard draft.wasActive || draft.isActive == false else {
                throw TimeTrackingRepositoryError.closedSegmentCannotReopen
            }
            try timeRepository.updateSegment(
                segmentID: draft.segmentID,
                taskID: taskID,
                startedAt: draft.startedAt,
                endedAt: draft.isActive ? nil : draft.endedAt,
                note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
            if let linkedRun = canonical.linkedRun {
                try rebindActivePomodoro(
                    linkedRun,
                    sessionID: canonical.segment.sessionID,
                    taskID: taskID,
                    fallbackStartedAt: draft.startedAt,
                    timeRepository: timeRepository,
                    now: now
                )
                if draft.wasActive, draft.isActive == false {
                    try pomodoroHandler.cancelIfNeeded(
                        sessionID: canonical.segment.sessionID,
                        runs: [linkedRun],
                        context: context,
                        now: draft.endedAt,
                        discardShortAttempt: false
                    )
                }
            }
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
            if let linkedRun = canonical.linkedRun {
                try PomodoroCommandHandler(
                    deviceID: resolvedDeviceID,
                    nowProvider: { now }
                ).discardIfNeeded(
                    sessionID: canonical.segment.sessionID,
                    runs: [linkedRun],
                    context: context
                )
            }
            try timeRepository.softDeleteSegment(segmentID: segmentID)
            return try outcome(
                subjectSegmentID: segmentID,
                before: before,
                referenceDate: now,
                timeRepository: timeRepository,
                pomodoroRepository: pomodoroRepository
            )
        }
    }

    private func rebindActivePomodoro(
        _ run: PomodoroRun,
        sessionID: UUID,
        taskID: UUID,
        fallbackStartedAt: Date,
        timeRepository: SwiftDataTimeTrackingRepository,
        now: Date
    ) throws {
        guard run.sessionID == sessionID,
              run.deletedAt == nil,
              run.endedAt == nil,
              run.state == .focusing || run.state == .interrupted
        else {
            return
        }
        run.taskID = taskID
        run.startedAt = try timeRepository
            .canonicalSessions(ids: [sessionID])
            .first?
            .startedAt ?? fallbackStartedAt
        run.markMutated(at: now, deviceID: resolvedDeviceID)
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
        try session.withFreshMutationContext { context in
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
