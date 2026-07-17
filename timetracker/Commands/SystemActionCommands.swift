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
            _ = try syncConflictService.recordLocalMutation(context: context, events: events)
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

@MainActor
struct SystemActionPostCommitEffects {
    /// Each effect runs after the system action has committed. A best-effort
    /// failure must not turn a durable action into a retryable failure.
    func apply(context: ModelContext, events: Set<StoreDomainEvent>) {
        guard events.isEmpty == false else { return }
        _ = CommittedMutationSnapshotRecorder().recordLocalMutation(
            context: context,
            events: events
        )
        _ = CommittedMutationSurfaceSynchronizer().synchronize(
            context: context,
            events: events
        )
        StoreMutationBroadcaster.publish(events: events)
    }
}

@MainActor
struct SystemActionCommandHandler {
    let writeAuthorization: StoreWriteAuthorization

    init(writeAuthorization: StoreWriteAuthorization = .applicationState) {
        self.writeAuthorization = writeAuthorization
    }

    @discardableResult
    func addInboxItem(
        title: String,
        container: ModelContainer,
        externalCommandKey: ExternalCommandKey? = nil,
        deviceID: String = DeviceIdentity.current
    ) throws -> InboxMutationOutcome {
        try StoreScopedInboxCommandCoordinator(
            container: container,
            writeAuthorization: writeAuthorization,
            deviceID: deviceID
        ).add(command: InboxCaptureCommand(
            title: title,
            externalCommandKey: externalCommandKey
        ))
    }

    @discardableResult
    func startTimer(
        taskID: UUID,
        source: TimeSessionSource = .timer,
        context: ModelContext
    ) throws -> UUID? {
        try startTimerMutation(
            taskID: taskID,
            source: source,
            container: context.container
        ).subjectSegmentID
    }

    func startTimerMutation(
        taskID: UUID,
        source: TimeSessionSource = .timer,
        container: ModelContainer
    ) throws -> StoreScopedTimerCommandOutcome {
        try StoreScopedTimerCommandCoordinator(
            container: container,
            writeAuthorization: writeAuthorization
        ).start(
            taskID: taskID,
            source: source
        )
    }

    @discardableResult
    func stopTimer(
        segmentID: UUID? = nil,
        taskID: UUID? = nil,
        context: ModelContext
    ) throws -> UUID? {
        try stopTimerMutation(
            segmentID: segmentID,
            taskID: taskID,
            container: context.container
        ).subjectSegmentID
    }

    func stopTimerMutation(
        segmentID: UUID? = nil,
        taskID: UUID? = nil,
        container: ModelContainer
    ) throws -> StoreScopedTimerCommandOutcome {
        try StoreScopedTimerCommandCoordinator(
            container: container,
            writeAuthorization: writeAuthorization
        ).stop(segmentID: segmentID, taskID: taskID)
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
