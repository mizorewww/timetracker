import Foundation
import SwiftData

extension TimeTrackerStore {
    @discardableResult
    func perform(event: StoreDomainEvent = .fullSync, _ action: () throws -> Void) -> Bool {
        perform(events: [event], action)
    }

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

    /// Resolves mutation events from the committed command outcome so stale
    /// facade caches cannot over- or under-report the domains that changed.
    /// Returning `nil` is a canonical no-op and skips refresh and sync recording.
    func performMutation<Outcome>(
        eventsForOutcome: (Outcome) -> Set<StoreDomainEvent>,
        _ action: () throws -> Outcome?
    ) -> Outcome? {
        let outcome: Outcome?
        do {
            outcome = try executeAuthorizedMutation(action)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
        guard let outcome else { return nil }

        let events = eventsForOutcome(outcome)
        if events.isEmpty == false {
            finishCommittedMutation(events: events)
        }
        return outcome
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
                try refresh(plan: refreshPlanner.plan(after: refreshEvents))
            } catch {
                errorMessage = String(
                    format: AppStrings.localized("error.savedRefreshFailed"),
                    error.localizedDescription
                )
            }
        }
        if let missingTaskRefreshError {
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                missingTaskRefreshError.localizedDescription
            )
        }
        return outcome.subjectSegmentID != nil
    }

    /// Refreshes and records a mutation that committed in a sibling context
    /// under the store-scoped lock. Empty events represent a canonical no-op
    /// and intentionally do not advance the sync generation.
    func finishStoreScopedMutation(events: Set<StoreDomainEvent>) {
        guard events.isEmpty == false else { return }
        finishCommittedMutation(events: events)
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
            try refreshCoordinator.refreshReadModels(self, plan: plan)
            if plan.validateSelection {
                validateSelectedTask()
            }
        } catch {
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                error.localizedDescription
            )
        }
    }

    /// Converges a scene after a sibling context may already have committed
    /// task metadata, without recording another mutation or starting
    /// post-refresh system and suggestion work.
    func refreshStoreScopedTaskReadModels() throws {
        let plan = StoreRefreshPlan(scopes: [.tasks])
        try refreshCoordinator.refreshReadModels(self, plan: plan)
        if plan.validateSelection {
            validateSelectedTask()
        }
    }

    private func executeAuthorizedMutation<Result>(
        _ action: () throws -> Result
    ) throws -> Result {
        try writeAuthorization.requireUserWritesAllowed()
        if let modelContext {
            return try modelContext.performAtomicMutation(action)
        }
        return try action()
    }

    private func finishCommittedMutation(events: Set<StoreDomainEvent>) {
        var postCommitError: Error?
        let plan = PerformanceSignpost.interval("Store refresh planning") {
            refreshPlanner.plan(after: events)
        }
        do {
            try refresh(plan: plan)
        } catch {
            postCommitError = error
        }
        do {
            try recordLocalSyncSnapshotIfNeeded(events: events)
        } catch {
            postCommitError = postCommitError ?? error
        }
        StoreMutationBroadcaster.publish(
            events: events,
            source: self
        )

        if let postCommitError {
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                postCommitError.localizedDescription
            )
        }
    }

    private func recordLocalSyncSnapshotIfNeeded(events: Set<StoreDomainEvent>) throws {
        guard let modelContext else { return }
        let snapshotEvents: Set<StoreDomainEvent> = scheduledSyncRefreshBatch == nil
            ? events
            : [.fullSync]
        let snapshotResult = try syncConflictService.recordLocalMutation(
            context: modelContext,
            events: snapshotEvents
        )
        switch snapshotResult {
        case let .recorded(prompt):
            pendingSyncConflict = prompt
        case .notRecorded:
            pendingSyncConflict = try syncConflictService.prompt()
        }
    }
}
