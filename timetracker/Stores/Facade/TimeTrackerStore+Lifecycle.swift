import Foundation
import OSLog
import SwiftData

private enum CommittedMutationProjectionDiagnostics {
    static let logger = Logger(
        subsystem: AppIdentity.loggingSubsystem,
        category: "CommittedMutationProjection"
    )
}

extension TimeTrackerStore {
    /// Whole-store maintenance mutation; failures go to the shared error slot.
    @discardableResult
    func perform(events: Set<StoreDomainEvent>, _ action: () throws -> Void) -> Bool {
        do {
            try executeAuthorizedMutation(action)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        finishCommittedMutation(events: events)
        return true
    }

    /// Runs a committed mutation while preserving its original failure for a
    /// scene-local caller to present. The outcome decides whether any domain
    /// refresh is required, so a successful no-op can avoid full invalidation.
    func performThrowingMutation<Outcome>(
        eventsForOutcome: (Outcome) -> Set<StoreDomainEvent>,
        _ action: () throws -> Outcome
    ) throws -> Outcome {
        let outcome = try executeAuthorizedMutation(action)
        let events = eventsForOutcome(outcome)
        if events.isEmpty == false {
            finishCommittedMutation(events: events)
        }
        return outcome
    }

    /// The mutation session for the configured store, or
    /// `StoreError.notConfigured` when the store has not been configured yet.
    func requireMutationSession() throws -> StoreMutationSession {
        guard let modelContext else { throw StoreError.notConfigured }
        return StoreMutationSession(
            container: modelContext.container,
            writeAuthorization: writeAuthorization
        )
    }

    /// Formats the standard post-commit refresh failure message.
    func savedRefreshFailedMessage(_ error: Error) -> String {
        String(
            format: AppStrings.localized("error.savedRefreshFailed"),
            error.localizedDescription
        )
    }

    /// Shared tail for store-scoped command methods: resolves the configured
    /// mutation session, runs the command, applies `finish` to the committed outcome,
    /// and maps any thrown error to `errorMessage`. Pass `onError` when the
    /// domain must converge stale read models before the message is assigned;
    /// it then owns the whole failure path, including the final assignment.
    @discardableResult
    func performStoreCommand<Outcome>(
        onError: ((Error) -> Void)? = nil,
        command: (StoreMutationSession) throws -> Outcome,
        finish: (Outcome) throws -> Void
    ) -> Outcome? {
        performStoreCommand(
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
    ) -> Result? {
        do {
            return try finishResult(command(requireMutationSession()))
        } catch {
            if let onError {
                onError(error)
            } else {
                errorMessage = error.localizedDescription
            }
            return nil
        }
    }

    /// Common store-scoped finish: publish the events carried by the
    /// committed outcome.
    @discardableResult
    func performStoreCommand<Outcome>(
        eventsForOutcome: (Outcome) -> Set<StoreDomainEvent>,
        onError: ((Error) -> Void)? = nil,
        command: (StoreMutationSession) throws -> Outcome
    ) -> Outcome? {
        performStoreCommand(onError: onError, command: command) { outcome in
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
        var missingTaskRefreshError: Error?
        if outcome.referencedTaskIDs.contains(where: { taskByID[$0] == nil }) {
            do {
                try refresh(plan: StoreRefreshPlan(scopes: [.tasks]))
            } catch {
                missingTaskRefreshError = error
            }
        }

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
                errorMessage = savedRefreshFailedMessage(error)
            }
        }
        if let missingTaskRefreshError {
            errorMessage = savedRefreshFailedMessage(missingTaskRefreshError)
        }
        return outcome.subjectSegmentID != nil
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
            errorMessage = savedRefreshFailedMessage(error)
        }
    }

    private func executeAuthorizedMutation<Result>(
        _ action: () throws -> Result
    ) throws -> Result {
        try PerformanceSignpost.interval("mutation.transaction") {
            try writeAuthorization.requireUserWritesAllowed()
            if let modelContext {
                return try modelContext.performAtomicMutation(
                    author: .localMutation,
                    action
                )
            }
            return try action()
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
            errorMessage = savedRefreshFailedMessage(postCommitError)
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
