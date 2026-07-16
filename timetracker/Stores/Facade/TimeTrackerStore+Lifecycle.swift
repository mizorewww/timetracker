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
    ) -> SyncConflictResolutionResult {
        do {
            guard let modelContext else { throw StoreError.notConfigured }
            let result = try syncConflictService.resolveSyncConflict(
                expectedConflictID: expectedConflictID,
                resolution: resolution,
                context: modelContext
            )
            guard result != .conflictChanged else {
                pendingSyncConflict = try syncConflictService.prompt()
                errorMessage = AppStrings.localized("sync.conflict.error.changed")
                return result
            }
            try refresh()
            pendingSyncConflict = nil
            lastSyncRefreshAt = Date()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    func forceUploadLocalDataToCloud() -> SyncRecoveryResult? {
        do {
            guard let modelContext else { throw StoreError.notConfigured }
            let result = try syncConflictService.forceUploadLocalData(context: modelContext)
            try refresh()
            pendingSyncConflict = nil
            lastSyncRefreshAt = Date()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func acceptCurrentCloudData() -> SyncRecoveryResult? {
        do {
            guard let modelContext else { throw StoreError.notConfigured }
            let result = try syncConflictService.acceptCurrentCloudData(context: modelContext)
            try refresh()
            pendingSyncConflict = nil
            lastSyncRefreshAt = Date()
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
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
