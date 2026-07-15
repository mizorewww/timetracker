import Foundation
import OSLog
import SwiftData

@MainActor
struct CommittedMutationSnapshotRecorder {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker",
        category: "CommittedMutationSnapshot"
    )

    private let syncConflictService: SyncConflictService

    init() {
        self.syncConflictService = SyncConflictService()
    }

    init(syncConflictService: SyncConflictService) {
        self.syncConflictService = syncConflictService
    }

    /// Snapshot persistence is a post-commit operation. Its failure must never
    /// make callers report that the already-durable user mutation failed.
    @discardableResult
    func recordLocalMutation(
        context: ModelContext,
        events: Set<StoreDomainEvent>
    ) -> Error? {
        do {
            try syncConflictService.recordLocalMutation(context: context, events: events)
            return nil
        } catch {
            Self.logger.error(
                "Failed to update the committed-mutation sync snapshot: \(error.localizedDescription, privacy: .public)"
            )
            return error
        }
    }
}

@MainActor
struct CommittedMutationSurfaceSynchronizer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker",
        category: "CommittedMutationSurfaces"
    )

    private let widgetCache: WidgetSnapshotCache?

    init(widgetCache: WidgetSnapshotCache? = nil) {
        self.widgetCache = widgetCache
    }

    /// System-surface refresh is post-commit work. A failure is reported for
    /// diagnostics but must not make a durable App Intent mutation look failed
    /// (which could prompt an unsafe retry of a non-idempotent action).
    @discardableResult
    func synchronize(
        context: ModelContext,
        events: Set<StoreDomainEvent>,
        now: Date = Date()
    ) -> Error? {
        do {
            let store = TimeTrackerStore()
            store.configureRepositoriesIfNeeded(context: context)
            if let error = try store.refreshCommittedMutationSurfaces(
                events: events,
                widgetCache: widgetCache,
                now: now
            ) {
                Self.logger.error(
                    "Failed to refresh a committed mutation on system surfaces: \(error.localizedDescription, privacy: .public)"
                )
                return error
            }
            return nil
        } catch {
            Self.logger.error(
                "Failed to refresh a committed mutation on system surfaces: \(error.localizedDescription, privacy: .public)"
            )
            return error
        }
    }
}

struct TimerActiveSetMutationService {
    func events(
        beforeActiveSegments: [TimeSegment],
        afterActiveSegments: [TimeSegment]
    ) -> Set<StoreDomainEvent> {
        let beforeByID = beforeActiveSegments.reduce(into: [UUID: TimeSegment]()) {
            $0[$1.id] = $1
        }
        let afterByID = afterActiveSegments.reduce(into: [UUID: TimeSegment]()) {
            $0[$1.id] = $1
        }
        let stoppedIDs = Set(beforeByID.keys).subtracting(afterByID.keys)
        let startedIDs = Set(afterByID.keys).subtracting(beforeByID.keys)
        var events = Set<StoreDomainEvent>()

        for id in stoppedIDs {
            guard let segment = beforeByID[id] else { continue }
            events.insert(.ledgerChanged(taskID: segment.taskID, dateInterval: nil, isVisible: true))
            events.insert(.pomodoroChanged(
                runID: nil,
                sessionID: segment.sessionID,
                taskID: segment.taskID
            ))
        }
        for id in startedIDs {
            guard let segment = afterByID[id] else { continue }
            events.insert(.ledgerChanged(taskID: segment.taskID, dateInterval: nil, isVisible: true))
            events.insert(.pomodoroChanged(
                runID: nil,
                sessionID: segment.sessionID,
                taskID: segment.taskID
            ))
        }
        return events
    }
}

@MainActor
struct SystemActionCommandHandler {
    @discardableResult
    func addInboxItem(
        title: String,
        context: ModelContext,
        deviceID: String = DeviceIdentity.current
    ) throws -> UUID? {
        try context.performAtomicMutation {
            try AppCloudSync.requireUserWritesAllowed()
            let existingItems = try context.fetch(FetchDescriptor<InboxItem>())
                .visibleDeduplicatedByID()
                .sorted { lhs, rhs in
                    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            return try InboxCommandHandler()
                .add(title: title, existingItems: existingItems, context: context, deviceID: deviceID)?
                .id
        }
    }

    @discardableResult
    func startTimer(
        taskID: UUID,
        allowParallelTimers: Bool,
        source: TimeSessionSource = .timer,
        context: ModelContext
    ) throws -> UUID? {
        try context.performAtomicMutation {
            try AppCloudSync.requireUserWritesAllowed()
            let taskRepository = SwiftDataTaskRepository(context: context)
            let availableTaskIDs = TaskTrackingAvailabilityService().availableTaskIDs(
                tasks: try taskRepository.allNodes()
            )
            guard availableTaskIDs.contains(taskID) else {
                throw SystemActionCommandError.taskNotFound
            }

            let timeRepository = SwiftDataTimeTrackingRepository(context: context)
            let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository)
            let activeSegments = try timeRepository.activeSegments()
            let existingSegmentID = activeSegments.first(where: { $0.taskID == taskID })?.id

            try TimerCommandHandler().startTask(
                taskID: taskID,
                allowParallelTimers: allowParallelTimers,
                activeSegments: activeSegments,
                pomodoroRuns: try pomodoroRepository.runs(),
                timeRepository: timeRepository,
                context: context,
                source: source
            )

            if let existingSegmentID {
                return existingSegmentID
            }
            return try timeRepository.activeSegments().first(where: { $0.taskID == taskID })?.id
        }
    }

    @discardableResult
    func stopTimer(
        taskID: UUID?,
        context: ModelContext
    ) throws -> UUID? {
        try context.performAtomicMutation {
            try AppCloudSync.requireUserWritesAllowed()
            let timeRepository = SwiftDataTimeTrackingRepository(context: context)
            let activeSegments = try timeRepository.activeSegments()
            guard let segment = taskID.flatMap({ taskID in
                activeSegments.first { $0.taskID == taskID }
            }) ?? activeSegments.last else {
                return nil
            }

            let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository)
            try TimerCommandHandler().stop(
                segment: segment,
                pomodoroRuns: try pomodoroRepository.runs(),
                timeRepository: timeRepository,
                context: context
            )
            return segment.id
        }
    }

    func allowParallelTimersPreference(context: ModelContext) throws -> Bool {
        let preferences = try context.fetch(FetchDescriptor<SyncedPreference>())
            .deduplicatedByID()
            .filter { $0.deletedAt == nil && SyncedPreferenceService.shouldSyncKey($0.key) }
        return AppPreferences(syncedPreferences: preferences).allowParallelTimers
    }
}

enum SystemActionCommandError: LocalizedError, Equatable {
    case taskNotFound

    var errorDescription: String? {
        switch self {
        case .taskNotFound:
            AppStrings.localized("systemAction.error.taskNotFound")
        }
    }
}
