import Foundation
import OSLog
import SwiftData

@MainActor
struct SystemActionPostCommitEffects {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "me.mezorewww.timetracker",
        category: "SystemActionPostCommit"
    )

    typealias SchedulerProvider = @MainActor (
        ModelContainer
    ) throws -> CommittedMutationSystemProjectionScheduler

    private let schedulerProvider: SchedulerProvider

    init() {
        schedulerProvider = { container in
            try CommittedMutationSystemProjectionSchedulerRegistry.shared
                .scheduler(for: container)
        }
    }

    init(schedulerProvider: @escaping SchedulerProvider) {
        self.schedulerProvider = schedulerProvider
    }

    /// The durable command has already committed. Sibling scenes receive a
    /// queued read-only catch-up, while persistent-history-backed projection
    /// lanes perform sync snapshot, Widget, Watch, and Live Activity work
    /// independently. Neither path may delay or reverse the command result.
    func apply(
        container: ModelContainer,
        events: Set<StoreDomainEvent>
    ) {
        guard events.isEmpty == false else { return }
        StoreMutationBroadcaster.publish(events: events)
        do {
            let scheduler = try schedulerProvider(container)
            scheduler.enqueue(
                CommittedMutationSystemProjectionReceipt(events: events)
            )
        } catch {
            Self.logger.error(
                "Could not schedule committed system-action projections: \(error.localizedDescription, privacy: .public)"
            )
        }
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

    /// Stops every currently running segment one committed mutation at a
    /// time, so partial success still leaves the store consistent.
    func stopAllTimersMutation(
        container: ModelContainer
    ) throws -> StopAllTimersOutcome {
        let readContext = ModelContext(container)
        let activeSegments = try SwiftDataTimeTrackingRepository(
            context: readContext
        ).activeSegments()
        var stoppedSegmentIDs: [UUID] = []
        var events: Set<StoreDomainEvent> = []
        for segment in activeSegments {
            let outcome = try stopTimerMutation(
                segmentID: segment.id,
                container: container
            )
            if outcome.subjectSegmentID == segment.id {
                stoppedSegmentIDs.append(segment.id)
                events.formUnion(outcome.events)
            }
        }
        return StopAllTimersOutcome(
            stoppedSegmentIDs: stoppedSegmentIDs,
            events: events
        )
    }
}

struct StopAllTimersOutcome: Equatable {
    let stoppedSegmentIDs: [UUID]
    let events: Set<StoreDomainEvent>

    var didMutate: Bool {
        stoppedSegmentIDs.isEmpty == false
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
