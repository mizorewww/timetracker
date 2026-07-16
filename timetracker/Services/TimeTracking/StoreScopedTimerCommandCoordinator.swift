import Foundation
import SwiftData

nonisolated struct TimerMutationSegmentSnapshot: Hashable, Sendable {
    let segmentID: UUID
    let sessionID: UUID
    let taskID: UUID

    init(segmentID: UUID, sessionID: UUID, taskID: UUID) {
        self.segmentID = segmentID
        self.sessionID = sessionID
        self.taskID = taskID
    }

    @MainActor
    init(segment: TimeSegment) {
        self.init(
            segmentID: segment.id,
            sessionID: segment.sessionID,
            taskID: segment.taskID
        )
    }
}

nonisolated struct StoreScopedTimerCommandOutcome: Hashable, Sendable {
    /// The active segment selected by Start, or the segment actually closed by
    /// Stop. A stale or ambiguous Stop has no subject and is a successful no-op.
    let subjectSegmentID: UUID?
    let createdSegment: TimerMutationSegmentSnapshot?
    let stoppedSegments: [TimerMutationSegmentSnapshot]

    var didMutate: Bool {
        createdSegment != nil || stoppedSegments.isEmpty == false
    }

    @MainActor
    var events: Set<StoreDomainEvent> {
        var events = Set<StoreDomainEvent>()
        for segment in stoppedSegments {
            events.formUnion(Self.events(for: segment))
        }
        if let createdSegment {
            events.formUnion(Self.events(for: createdSegment))
        }
        return events
    }

    @MainActor
    private static func events(
        for segment: TimerMutationSegmentSnapshot
    ) -> Set<StoreDomainEvent> {
        [
            .ledgerChanged(
                taskID: segment.taskID,
                dateInterval: nil,
                isVisible: true
            ),
            .pomodoroChanged(
                runID: nil,
                sessionID: segment.sessionID,
                taskID: segment.taskID
            ),
        ]
    }
}

private enum StoreScopedTimerCommandCoordinatorError: Error {
    case inconsistentAdmissionPlan
}

/// Linearizes one timer read-plan-write sequence for one concrete SwiftData
/// store. Every decision is made from a fresh context created after acquiring
/// the store lock; no facade or caller cache participates in admission.
@MainActor
struct StoreScopedTimerCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization
    let deviceID: String?

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        deviceID: String? = nil
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
        self.deviceID = deviceID
    }

    func start(
        taskID: UUID,
        allowParallelTimers: Bool,
        sameTaskBehavior: TimerSameTaskStartBehavior = .reuseOldest,
        source: TimeSessionSource = .timer
    ) throws -> StoreScopedTimerCommandOutcome {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )

        return try transaction.withFreshContext { context in
            let taskRepository = SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID
            )
            let tasks = try taskRepository.allNodes()
            guard TaskTrackingAvailabilityService()
                .trackableTaskIDs(tasks: tasks)
                .contains(taskID) else {
                throw SystemActionCommandError.taskNotFound
            }

            let timeRepository = SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: deviceID
            )
            let pomodoroRepository = SwiftDataPomodoroRepository(
                context: context,
                timeRepository: timeRepository,
                deviceID: deviceID
            )
            let activeSegments = try timeRepository.activeSegments()
            let activeByID = Dictionary(
                uniqueKeysWithValues: activeSegments.map { ($0.id, $0) }
            )
            let plan = TimerAdmissionPolicy().startPlan(
                taskID: taskID,
                mode: allowParallelTimers ? .parallel : .exclusive,
                sameTaskBehavior: sameTaskBehavior,
                activeSegments: activeSegments.map(Self.admissionSnapshot)
            )
            let pomodoroRuns = try pomodoroRepository.runs()
            let stoppedSegments = try applyStops(
                plan.segmentsToStop,
                activeByID: activeByID,
                pomodoroRuns: pomodoroRuns,
                timeRepository: timeRepository,
                context: context
            )

            switch plan.decision {
            case .reuse(let survivor):
                guard let segment = activeByID[survivor.segmentID] else {
                    throw StoreScopedTimerCommandCoordinatorError
                        .inconsistentAdmissionPlan
                }
                return StoreScopedTimerCommandOutcome(
                    subjectSegmentID: segment.id,
                    createdSegment: nil,
                    stoppedSegments: stoppedSegments
                )
            case .createNew:
                let segment = try timeRepository.startTask(
                    taskID: taskID,
                    source: source
                )
                return StoreScopedTimerCommandOutcome(
                    subjectSegmentID: segment.id,
                    createdSegment: TimerMutationSegmentSnapshot(segment: segment),
                    stoppedSegments: stoppedSegments
                )
            }
        }
    }

    func stop(
        segmentID: UUID? = nil,
        taskID: UUID? = nil
    ) throws -> StoreScopedTimerCommandOutcome {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )

        return try transaction.withFreshContext { context in
            guard segmentID == nil || taskID == nil else {
                return Self.noOpOutcome
            }

            let timeRepository = SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: deviceID
            )
            let activeSegments = try timeRepository.activeSegments()
            let admissionSegments = activeSegments.map(Self.admissionSnapshot)
            let stopPlan: TimerStopPlan

            if let segmentID {
                stopPlan = TimerAdmissionPolicy().stopPlan(
                    target: .segment(segmentID),
                    activeSegments: admissionSegments
                )
            } else if let taskID {
                let candidatePlan = TimerAdmissionPolicy().stopPlan(
                    target: .task(taskID),
                    activeSegments: admissionSegments
                )
                guard candidatePlan.segmentsToStop.count == 1 else {
                    return Self.noOpOutcome
                }
                stopPlan = candidatePlan
            } else {
                guard admissionSegments.count == 1,
                      let onlySegment = admissionSegments.first else {
                    return Self.noOpOutcome
                }
                stopPlan = TimerAdmissionPolicy().stopPlan(
                    target: .segment(onlySegment.segmentID),
                    activeSegments: admissionSegments
                )
            }

            guard stopPlan.segmentsToStop.count == 1,
                  let target = stopPlan.segmentsToStop.first,
                  let segment = activeSegments.first(where: {
                      $0.id == target.segmentID
                  }) else {
                return Self.noOpOutcome
            }

            let pomodoroRepository = SwiftDataPomodoroRepository(
                context: context,
                timeRepository: timeRepository,
                deviceID: deviceID
            )
            try TimerCommandHandler(deviceID: deviceID).stop(
                segment: segment,
                pomodoroRuns: try pomodoroRepository.runs(),
                timeRepository: timeRepository,
                context: context
            )
            let stopped = TimerMutationSegmentSnapshot(segment: segment)
            return StoreScopedTimerCommandOutcome(
                subjectSegmentID: stopped.segmentID,
                createdSegment: nil,
                stoppedSegments: [stopped]
            )
        }
    }

    private func applyStops(
        _ stops: [TimerActiveSegmentSnapshot],
        activeByID: [UUID: TimeSegment],
        pomodoroRuns: [PomodoroRun],
        timeRepository: SwiftDataTimeTrackingRepository,
        context: ModelContext
    ) throws -> [TimerMutationSegmentSnapshot] {
        let handler = TimerCommandHandler(deviceID: deviceID)
        var stoppedSegments: [TimerMutationSegmentSnapshot] = []
        for stop in stops {
            guard let segment = activeByID[stop.segmentID] else {
                throw StoreScopedTimerCommandCoordinatorError
                    .inconsistentAdmissionPlan
            }
            try handler.stop(
                segment: segment,
                pomodoroRuns: pomodoroRuns,
                timeRepository: timeRepository,
                context: context
            )
            stoppedSegments.append(TimerMutationSegmentSnapshot(segment: segment))
        }
        return stoppedSegments
    }

    private static func admissionSnapshot(
        _ segment: TimeSegment
    ) -> TimerActiveSegmentSnapshot {
        TimerActiveSegmentSnapshot(
            segmentID: segment.id,
            sessionID: segment.sessionID,
            taskID: segment.taskID,
            startedAt: segment.startedAt
        )
    }

    private static let noOpOutcome = StoreScopedTimerCommandOutcome(
        subjectSegmentID: nil,
        createdSegment: nil,
        stoppedSegments: []
    )
}
