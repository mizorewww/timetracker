import Foundation
import OSLog
import SwiftData

@MainActor
struct SystemActionPostCommitEffects {
    private static let logger = Logger(
        subsystem: AppIdentity.loggingSubsystem,
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
            scheduler.enqueue(events: events)
        } catch {
            Self.logger.error(
                "Could not schedule committed system-action projections: \(error.localizedDescription, privacy: .public)"
            )
        }
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
