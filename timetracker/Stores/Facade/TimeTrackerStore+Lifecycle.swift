import Foundation
import OSLog
import SwiftData

private enum CommittedMutationProjectionDiagnostics {
    static let logger = Logger(
        subsystem: AppIdentity.loggingSubsystem,
        category: "CommittedMutationProjection"
    )
}

private enum UnpresentedFailureDiagnostics {
    static let logger = Logger(
        subsystem: AppIdentity.loggingSubsystem,
        category: "UnpresentedFailure"
    )
}

extension TimeTrackerStore {
    /// The mutation session for the configured store, or
    /// `StoreError.notConfigured` when the store has not been configured yet.
    func requireMutationSession() throws -> StoreMutationSession {
        guard let modelContext else { throw StoreError.notConfigured }
        return StoreMutationSession(
            container: modelContext.container,
            writeAuthorization: writeAuthorization
        )
    }

    /// Logs a failure that has no initiating view to present it: lifecycle,
    /// sync and timer work that the next pass retries.
    func logUnpresentedFailure(_ operation: String, _ error: Error) {
        UnpresentedFailureDiagnostics.logger.error(
            "\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
        )
    }

    /// Read-model refreshes run after a command already committed, or while
    /// converging after a rejected one. Their failure never changes the
    /// command's result and the next refresh retries, so it is only logged.
    func logReadModelRefreshFailure(_ error: Error) {
        logUnpresentedFailure("Read-model refresh", error)
    }

    /// Runs a convergence refresh whose failure must not change a command's
    /// result; see `logReadModelRefreshFailure`.
    func refreshLoggingFailure(plan: StoreRefreshPlan) {
        do {
            try refresh(plan: plan)
        } catch {
            logReadModelRefreshFailure(error)
        }
    }

    /// Shared tail for store-scoped command methods: resolves the configured
    /// mutation session, runs the command, applies `finish` to the committed
    /// outcome, and rethrows any failure to the caller. Pass `onError` when the
    /// domain must converge stale read models before the error propagates.
    @discardableResult
    func performStoreCommand<Outcome>(
        onError: ((Error) -> Void)? = nil,
        command: (StoreMutationSession) throws -> Outcome,
        finish: (Outcome) throws -> Void
    ) throws -> Outcome {
        try performStoreCommand(
            onError: onError,
            command: command,
            finishResult: { outcome in
                try finish(outcome)
                return outcome
            }
        )
    }

    /// `performStoreCommand` variant whose committed outcome maps to the
    /// command's own result (for example a timer command's subject lookup).
    @discardableResult
    func performStoreCommand<Outcome, Result>(
        onError: ((Error) -> Void)? = nil,
        command: (StoreMutationSession) throws -> Outcome,
        finishResult: (Outcome) throws -> Result
    ) throws -> Result {
        do {
            return try finishResult(command(requireMutationSession()))
        } catch {
            onError?(error)
            throw error
        }
    }

    /// Common store-scoped finish: publish the events carried by the
    /// committed outcome.
    @discardableResult
    func performStoreCommand<Outcome>(
        eventsForOutcome: (Outcome) -> Set<StoreDomainEvent>,
        onError: ((Error) -> Void)? = nil,
        command: (StoreMutationSession) throws -> Outcome
    ) throws -> Outcome {
        try performStoreCommand(onError: onError, command: command) { outcome in
            finishStoreScopedMutation(events: eventsForOutcome(outcome))
        }
    }

    /// Applies the result of a timer transaction that already committed in a
    /// fresh sibling context under the store-scoped timer lock.
    ///
    /// A pure reuse or rejected stale target has no durable mutation to record,
    /// but still refreshes timer read models so a scene with an older context
    /// converges on the canonical active set.
    @discardableResult
    func finishStoreScopedTimerCommand(
        _ outcome: StoreScopedTimerCommandOutcome
    ) -> Bool {
        refreshTasksIfAnyAreMissing(outcome.referencedTaskIDs)
        if outcome.didMutate {
            finishCommittedMutation(events: outcome.events)
        } else {
            let refreshEvents: Set<StoreDomainEvent> = [
                .ledgerChanged(taskID: nil, dateInterval: nil, isVisible: true),
                .pomodoroChanged(runID: nil, sessionID: nil, taskID: nil),
            ]
            do {
                try refresh(plan: StoreRefreshPlanner.plan(after: refreshEvents))
            } catch {
                logReadModelRefreshFailure(error)
            }
        }
        return outcome.subjectSegmentID != nil
    }

    /// A command that committed in a fresh context can reference a task this
    /// scene has not loaded yet (for example one created by another writer).
    /// Load tasks before the mutation refresh so its read models resolve them.
    func refreshTasksIfAnyAreMissing(_ taskIDs: Set<UUID>) {
        guard taskIDs.contains(where: { taskByID[$0] == nil }) else { return }
        refreshLoggingFailure(plan: StoreRefreshPlan(scopes: [.tasks]))
    }

    /// Refreshes the scene and schedules projection work for a mutation that
    /// committed in a sibling context under the store-scoped lock. Empty
    /// events represent a canonical no-op and do not enqueue a generation.
    func finishStoreScopedMutation(
        events: Set<StoreDomainEvent>,
        forcedSystemSinks:
        Set<CommittedMutationSystemProjectionSink> = []
    ) {
        guard events.isEmpty == false else { return }
        finishCommittedMutation(
            events: events,
            forcedSystemSinks: forcedSystemSinks
        )
    }

    /// Converges scene read models after another context may have changed the
    /// timer set before this locked command entered. This is refresh-only work:
    /// it must not advance the durable sync generation or change command success.
    func refreshStoreScopedTimerReadModels(includingTasks: Bool = false) {
        do {
            var scopes: Set<StoreRefreshScope> = [.ledgerVisible, .pomodoro]
            if includingTasks {
                scopes.insert(.tasks)
            }
            let plan = StoreRefreshPlan(scopes: scopes)
            try StoreRefreshCoordinator.refreshReadModels(self, plan: plan)
            if plan.validateSelection {
                validateSelectedTask()
            }
        } catch {
            logReadModelRefreshFailure(error)
        }
    }

    private func finishCommittedMutation(
        events: Set<StoreDomainEvent>,
        forcedSystemSinks:
        Set<CommittedMutationSystemProjectionSink> = []
    ) {
        var postCommitError: Error?
        let plan = PerformanceSignpost.interval("Store refresh planning") {
            StoreRefreshPlanner.plan(after: events)
        }
        do {
            try StoreRefreshCoordinator.refresh(
                self,
                plan: plan
            )
        } catch {
            postCommitError = error
        }
        StoreMutationBroadcaster.publish(
            events: events,
            source: self
        )
        enqueueCommittedMutationSystemProjections(
            events: events,
            forcedSystemSinks: forcedSystemSinks
        )

        if let postCommitError {
            logReadModelRefreshFailure(postCommitError)
        }
    }

    func enqueueCommittedMutationSystemProjections(
        events: Set<StoreDomainEvent>,
        forcedSystemSinks:
        Set<CommittedMutationSystemProjectionSink> = []
    ) {
        let scheduler: CommittedMutationSystemProjectionScheduler
        if let committedMutationSystemProjectionScheduler {
            scheduler = committedMutationSystemProjectionScheduler
        } else {
            guard writeAuthorization.usesApplicationState, let modelContext else { return }
            do {
                scheduler = try
                    CommittedMutationSystemProjectionSchedulerRegistry.shared
                    .scheduler(for: modelContext.container)
            } catch {
                CommittedMutationProjectionDiagnostics.logger.error(
                    "Could not schedule committed system projections: \(error.localizedDescription, privacy: .public)"
                )
                return
            }
        }
        scheduler.enqueue(
            events: events,
            forcedSinks: forcedSystemSinks
        )
    }
}
