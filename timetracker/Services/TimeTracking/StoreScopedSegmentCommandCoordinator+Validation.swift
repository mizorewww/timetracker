import Foundation
import SwiftData

extension StoreScopedSegmentCommandCoordinator {
    func requiredCanonicalState(
        baseline: SegmentEditorDraftBaseline,
        timeRepository: SwiftDataTimeTrackingRepository,
        pomodoroRepository: SwiftDataPomodoroRepository
    ) throws -> (segment: TimeSegment, linkedRun: PomodoroRun?) {
        guard baseline.sessionMutationID != nil else {
            throw SegmentMutationError.staleDraft
        }
        return try requiredCanonicalState(
            segmentID: baseline.segmentID,
            expectedBaseline: baseline,
            timeRepository: timeRepository,
            pomodoroRepository: pomodoroRepository
        )
    }

    func requiredCanonicalState(
        segmentID: UUID,
        expectedBaseline: SegmentEditorDraftBaseline?,
        timeRepository: SwiftDataTimeTrackingRepository,
        pomodoroRepository: SwiftDataPomodoroRepository
    ) throws -> (segment: TimeSegment, linkedRun: PomodoroRun?) {
        guard let segment = try timeRepository.segments(ids: [segmentID]).first,
              let session = try timeRepository.sessions(ids: [segment.sessionID]).first
        else {
            throw SegmentMutationError.staleDraft
        }
        let linkedRuns = try pomodoroRepository.activeRuns().filter { run in
            run.sessionID == segment.sessionID
        }
        guard linkedRuns.count <= 1,
              linkedRuns.allSatisfy({
                  $0.state == .focusing || $0.state == .interrupted
              })
        else {
            throw SegmentMutationError.inconsistentSession
        }
        let linkedRun = linkedRuns.first
        let phase = linkedRun.map(PomodoroPhaseToken.init)
        if let expectedBaseline {
            guard expectedBaseline.sessionMutationID != nil,
                  expectedBaseline.matches(
                      segment: segment,
                      sessionMutationID: session.clientMutationID,
                      pomodoroPhase: phase
                  )
            else {
                throw SegmentMutationError.staleDraft
            }
        }
        return (segment, linkedRun)
    }

    func validateUpdate(
        draft: SegmentEditorDraft,
        taskID: UUID,
        canonicalSegment: TimeSegment,
        now: Date,
        context: ModelContext
    ) throws {
        guard draft.wasActive || draft.isActive == false else {
            throw TimeTrackingRepositoryError.closedSegmentCannotReopen
        }
        let endedAt = draft.isActive ? nil : draft.endedAt
        switch TrackedTimePolicy.validateWrite(
            startedAt: draft.startedAt,
            endedAt: endedAt,
            now: now
        ) {
        case .valid:
            break
        case .invalidRange:
            throw TimeTrackingRepositoryError.invalidTimeRange
        case .futureTime:
            if draft.isActive {
                throw SegmentMutationError.activeTimerStartInFuture
            }
            throw TimeTrackingRepositoryError.futureTime
        }

        let isRetainingHistoricalAssignment =
            draft.isActive == false && canonicalSegment.taskID == taskID
        if isRetainingHistoricalAssignment {
            return
        }
        let taskRepository = SwiftDataTaskRepository(
            context: context,
            deviceID: resolvedDeviceID
        )
        let tasks = try taskRepository.allNodes()
        guard try TaskTrackingAvailabilityService()
            .directWorkTaskIDs(
                tasks: tasks,
                recurrenceRules: taskRepository.taskRecurrenceRules(),
                recurrenceOccurrences:
                taskRepository.taskRecurrenceOccurrences()
            )
            .contains(taskID)
        else {
            throw TimeTrackingRepositoryError.taskUnavailable
        }
    }

    func mutationState(
        sessionIDs: Set<UUID>,
        activeRuns: [PomodoroRun],
        timeRepository: SwiftDataTimeTrackingRepository
    ) throws -> (
        segments: [UUID: LedgerSegmentMutationSnapshot],
        runs: [UUID: SegmentPomodoroMutationSnapshot]
    ) {
        let impactedSegments = try timeRepository.segments(sessionIDs: sessionIDs)
        let segments = impactedSegments.reduce(
            into: [UUID: LedgerSegmentMutationSnapshot]()
        ) { result, segment in
            result[segment.id] = LedgerSegmentMutationSnapshot(segment: segment)
        }
        let impactedRuns = activeRuns.filter {
            $0.sessionID.map(sessionIDs.contains) == true
        }
        let runs = impactedRuns.reduce(
            into: [UUID: SegmentPomodoroMutationSnapshot]()
        ) { result, run in
            result[run.id] = SegmentPomodoroMutationSnapshot(run: run)
        }
        return (segments, runs)
    }

    func validatedRunBySessionID(
        activeRuns: [PomodoroRun],
        sessionIDs: Set<UUID>
    ) throws -> [UUID: PomodoroRun] {
        var result = [UUID: PomodoroRun]()
        for sessionID in sessionIDs {
            let runs = activeRuns.filter { $0.sessionID == sessionID }
            guard runs.count <= 1,
                  runs.allSatisfy({
                      $0.state == .focusing || $0.state == .interrupted
                  })
            else {
                throw SegmentMutationError.inconsistentSession
            }
            result[sessionID] = runs.first
        }
        return result
    }
}
