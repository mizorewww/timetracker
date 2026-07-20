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
    let subjectSegment: TimerMutationSegmentSnapshot?
    let createdSegment: TimerMutationSegmentSnapshot?
    let stoppedSegments: [TimerMutationSegmentSnapshot]
    let tombstonedSegments: [LedgerSegmentMutationSnapshot]

    init(
        subjectSegment: TimerMutationSegmentSnapshot?,
        createdSegment: TimerMutationSegmentSnapshot?,
        stoppedSegments: [TimerMutationSegmentSnapshot],
        tombstonedSegments: [LedgerSegmentMutationSnapshot] = []
    ) {
        self.subjectSegment = subjectSegment
        self.createdSegment = createdSegment
        self.stoppedSegments = stoppedSegments
        self.tombstonedSegments = tombstonedSegments
    }

    var subjectSegmentID: UUID? {
        subjectSegment?.segmentID
    }

    var referencedTaskIDs: Set<UUID> {
        var taskIDs = Set(stoppedSegments.map(\.taskID))
        if let subjectSegment {
            taskIDs.insert(subjectSegment.taskID)
        }
        if let createdSegment {
            taskIDs.insert(createdSegment.taskID)
        }
        taskIDs.formUnion(tombstonedSegments.map(\.taskID))
        return taskIDs
    }

    var didMutate: Bool {
        createdSegment != nil ||
            stoppedSegments.isEmpty == false ||
            tombstonedSegments.isEmpty == false
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
        for segment in tombstonedSegments {
            events.insert(Self.historyEvent(for: segment))
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

    @MainActor
    private static func historyEvent(
        for segment: LedgerSegmentMutationSnapshot
    ) -> StoreDomainEvent {
        let end = max(segment.startedAt, segment.endedAt ?? segment.startedAt)
        return .ledgerChanged(
            taskID: segment.taskID,
            dateInterval: StoreInvalidationRange(
                start: segment.startedAt,
                end: end
            ),
            isVisible: false
        )
    }
}

private enum StoreScopedTimerCommandCoordinatorError: Error {
    case inconsistentAdmissionPlan
}

/// Resolves timer admission settings only after a writer owns the store lock.
/// A scene, Watch command, or App Intent may have observed an older preference
/// snapshot while it was waiting to commit.
@MainActor
enum TimerAdmissionPreferenceResolver {
    static func allowParallelTimers(in context: ModelContext) throws -> Bool {
        let preferences = try context.fetch(FetchDescriptor<SyncedPreference>())
            .deduplicatedByID()
            .filter {
                $0.deletedAt == nil && SyncedPreferenceService.shouldSyncKey($0.key)
            }
        return AppPreferences(syncedPreferences: preferences).allowParallelTimers
    }
}

/// Linearizes one timer read-plan-write sequence for one concrete SwiftData
/// store. Every decision is made from a fresh context created after acquiring
/// the store lock; no facade or caller cache participates in admission.
@MainActor
struct StoreScopedTimerCommandCoordinator {
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

    func start(
        taskID: UUID,
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
            let mutationDate = nowProvider()
            let taskRepository = SwiftDataTaskRepository(
                context: context,
                deviceID: deviceID
            )
            let tasks = try taskRepository.allNodes()
            guard TaskTrackingAvailabilityService()
                .directWorkTaskIDs(
                    tasks: tasks,
                    recurrenceRules: try taskRepository.taskRecurrenceRules(),
                    recurrenceOccurrences:
                        try taskRepository.taskRecurrenceOccurrences()
                )
                .contains(taskID) else {
                throw SystemActionCommandError.taskNotFound
            }

            let timeRepository = SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: deviceID,
                nowProvider: { mutationDate }
            )
            let pomodoroRepository = SwiftDataPomodoroRepository(
                context: context,
                timeRepository: timeRepository,
                deviceID: deviceID,
                nowProvider: { mutationDate }
            )
            let activeSegments = try timeRepository.activeSegments()
            let activeByID = Dictionary(
                uniqueKeysWithValues: activeSegments.map { ($0.id, $0) }
            )
            let allowParallelTimers = try TimerAdmissionPreferenceResolver
                .allowParallelTimers(in: context)
            let plan = TimerAdmissionPolicy().startPlan(
                taskID: taskID,
                mode: allowParallelTimers ? .parallel : .exclusive,
                sameTaskBehavior: sameTaskBehavior,
                activeSegments: activeSegments.map(Self.admissionSnapshot)
            )
            let pomodoroRuns = try pomodoroRepository.openRuns(
                sessionIDs: Set(plan.segmentsToStop.map(\.sessionID))
            )
            let stoppedSegments = try applyStops(
                plan.segmentsToStop,
                activeByID: activeByID,
                pomodoroRuns: pomodoroRuns,
                timeRepository: timeRepository,
                context: context,
                mutationDate: mutationDate
            )

            switch plan.decision {
            case .reuse(let survivor):
                guard let segment = activeByID[survivor.segmentID] else {
                    throw StoreScopedTimerCommandCoordinatorError
                        .inconsistentAdmissionPlan
                }
                let survivorSnapshot = TimerMutationSegmentSnapshot(
                    segment: segment
                )
                return StoreScopedTimerCommandOutcome(
                    subjectSegment: survivorSnapshot,
                    createdSegment: nil,
                    stoppedSegments: stoppedSegments
                )
            case .createNew:
                let segment: TimeSegment
                var tombstonedSegments: [LedgerSegmentMutationSnapshot] = []
                if sameTaskBehavior == .reuseOldest,
                   let mutation = try timeRepository.startByCoalescingRapidRestart(
                       taskID: taskID,
                       source: source,
                       hasActiveSegmentForTask: activeSegments.contains {
                           $0.taskID == taskID
                       }
                   ) {
                    segment = mutation.replacement
                    tombstonedSegments = [mutation.tombstonedSegment]
                } else {
                    segment = try timeRepository.startTask(
                        taskID: taskID,
                        source: source
                    )
                }
                let createdSegment = TimerMutationSegmentSnapshot(segment: segment)
                return StoreScopedTimerCommandOutcome(
                    subjectSegment: createdSegment,
                    createdSegment: createdSegment,
                    stoppedSegments: stoppedSegments,
                    tombstonedSegments: tombstonedSegments
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
            let mutationDate = nowProvider()
            guard segmentID == nil || taskID == nil else {
                return Self.noOpOutcome
            }

            let timeRepository = SwiftDataTimeTrackingRepository(
                context: context,
                deviceID: deviceID,
                nowProvider: { mutationDate }
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
                deviceID: deviceID,
                nowProvider: { mutationDate }
            )
            try TimerCommandHandler(
                deviceID: deviceID,
                nowProvider: { mutationDate }
            ).stop(
                segment: segment,
                pomodoroRuns: try pomodoroRepository.openRuns(
                    sessionIDs: [segment.sessionID]
                ),
                timeRepository: timeRepository,
                context: context
            )
            let stopped = TimerMutationSegmentSnapshot(segment: segment)
            return StoreScopedTimerCommandOutcome(
                subjectSegment: stopped,
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
        context: ModelContext,
        mutationDate: Date
    ) throws -> [TimerMutationSegmentSnapshot] {
        let handler = TimerCommandHandler(
            deviceID: deviceID,
            nowProvider: { mutationDate }
        )
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
        subjectSegment: nil,
        createdSegment: nil,
        stoppedSegments: []
    )
}
