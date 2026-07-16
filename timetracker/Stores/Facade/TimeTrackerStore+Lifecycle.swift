import Foundation
import SwiftData

extension TimeTrackerStore {
    func refreshQuietly() {
        do {
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshForForeground() async {
        refreshQuietly()
        reconcileActivePomodoro(now: Date())
        await refreshCloudAccountStatus()
    }

    @discardableResult
    func refreshCloudAccountStatus(
        client: CloudAccountStatusClient? = nil,
        checkedAt: Date = Date()
    ) async -> CloudAccountCheckOutcome {
        let resolvedClient: CloudAccountStatusClient
        if let client {
            resolvedClient = client
        } else {
            resolvedClient = .live(containerIdentifier: AppCloudSync.containerIdentifier)
        }
        let requestID = UUID()
        cloudAccountCheckRequestID = requestID
        let outcome = await AppCloudSync.checkAccountStatus(
            client: resolvedClient,
            checkedAt: checkedAt
        )
        if cloudAccountCheckRequestID == requestID {
            cloudAccountCheck = outcome
        }
        return outcome
    }

    @discardableResult
    func resolveSyncConflict(
        expectedConflictID: UUID?,
        resolution: SyncConflictResolution
    ) throws -> SyncConflictResolutionResult {
        guard let modelContext else { throw StoreError.notConfigured }
        let result = try syncConflictService.resolveSyncConflict(
            expectedConflictID: expectedConflictID,
            resolution: resolution,
            context: modelContext
        )
        guard result != .conflictChanged else {
            pendingSyncConflict = try syncConflictService.prompt()
            return result
        }
        try refresh()
        pendingSyncConflict = nil
        return result
    }

    func refresh() throws {
        try refresh(plan: refreshPlanner.plan(after: [.fullSync]))
    }

    func refresh(plan: StoreRefreshPlan) throws {
        try refreshCoordinator.refresh(self, plan: plan)
    }

    func validateSelectedTask() {
        if selectedTaskID == nil {
            selectedTaskID = preferredTaskIDForSelection()
        } else if let selectedTaskID, isTaskDetailRouteValid(selectedTaskID) == false {
            self.selectedTaskID = preferredTaskIDForSelection()
        }

        if let detailTaskID = tasksRoute?.taskID, isTaskDetailRouteValid(detailTaskID) == false {
            tasksRoute = nil
        }
    }

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
    func refreshStoreScopedTimerReadModels() {
        do {
            try refresh(plan: StoreRefreshPlan(scopes: [.ledgerVisible, .pomodoro]))
        } catch {
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                error.localizedDescription
            )
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

        if let postCommitError {
            errorMessage = String(
                format: AppStrings.localized("error.savedRefreshFailed"),
                postCommitError.localizedDescription
            )
        }
    }

    @discardableResult
    func fail(_ error: StoreError) -> Bool {
        errorMessage = error.localizedDescription
        return false
    }

    func requiredTaskRepository() throws -> TaskRepository {
        guard let taskRepository else { throw StoreError.notConfigured }
        return taskRepository
    }

    func requiredTimeRepository() throws -> TimeTrackingRepository {
        guard let timeRepository else { throw StoreError.notConfigured }
        return timeRepository
    }

    func requiredPomodoroRepository() throws -> PomodoroRepository {
        guard let pomodoroRepository else { throw StoreError.notConfigured }
        return pomodoroRepository
    }

    enum StoreError: LocalizedError {
        case notConfigured
        case taskSelectionRequired
        case pomodoroTaskSelectionRequired
        case invalidTimeRange
        case activeTimerStartInFuture
        case closedSegmentCannotReopen
        case taskCategoryNameRequired
        case invalidInboxSuggestion
        case taskTrackingUnavailable

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "TimeTrackerStore has not been configured with a ModelContext."
            case .taskSelectionRequired:
                Self.localized("task.selectRequired")
            case .pomodoroTaskSelectionRequired:
                Self.localized("task.selectBeforePomodoro")
            case .invalidTimeRange:
                Self.localized("time.endAfterStart")
            case .activeTimerStartInFuture:
                Self.localized("segment.error.startNotFuture")
            case .closedSegmentCannotReopen:
                Self.localized("segment.error.cannotReopen")
            case .taskCategoryNameRequired:
                Self.localized("taskCategory.nameRequired")
            case .invalidInboxSuggestion:
                Self.localized("inbox.suggestion.error.noValidTask")
            case .taskTrackingUnavailable:
                Self.localized("task.archived.trackingUnavailable")
            }
        }

        private static func localized(_ key: String) -> String {
            NSLocalizedString(key, comment: "")
        }
    }

    private func recordLocalSyncSnapshotIfNeeded(events: Set<StoreDomainEvent>) throws {
        guard let modelContext else { return }
        let snapshotEvents: Set<StoreDomainEvent> = scheduledSyncRefreshReason == nil
            ? events
            : [.fullSync]
        try syncConflictService.recordLocalMutation(context: modelContext, events: snapshotEvents)
        pendingSyncConflict = try syncConflictService.prompt()
    }
}
