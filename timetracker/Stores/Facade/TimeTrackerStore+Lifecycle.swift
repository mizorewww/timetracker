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

    func forceCloudSyncRefresh() async -> String {
        await refreshCloudAccountStatus()
        refreshQuietly()
        let storage = syncStatus.isCloudBacked ? AppStrings.localized("sync.storage.iCloud") : AppStrings.localized("sync.storage.local")
        return String(format: AppStrings.localized("sync.refreshSummary"), storage, syncStatus.accountStatus)
    }

    func refreshCloudAccountStatus() async {
        await AppCloudSync.refreshAccountStatus()
        cloudAccountStatus = AppCloudSync.accountStatus
        lastSyncRefreshAt = Date()
    }

    func resolveSyncConflict(_ resolution: SyncConflictResolution) {
        do {
            guard let modelContext else { throw StoreError.notConfigured }
            try syncConflictService.resolve(resolution, context: modelContext)
            try refresh()
            pendingSyncConflict = nil
        } catch {
            errorMessage = error.localizedDescription
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
        } else if let selectedTaskID, taskByID[selectedTaskID] == nil {
            self.selectedTaskID = preferredTaskIDForSelection()
        }

        if let desktopTaskDetailID, taskByID[desktopTaskDetailID] == nil {
            self.desktopTaskDetailID = nil
        }
    }

    @discardableResult
    func perform(event: StoreDomainEvent = .fullSync, _ action: () throws -> Void) -> Bool {
        perform(events: [event], action)
    }

    @discardableResult
    func perform(events: Set<StoreDomainEvent>, _ action: () throws -> Void) -> Bool {
        do {
            try AppCloudSync.requireUserWritesAllowed()
            if let modelContext {
                try modelContext.performAtomicMutation {
                    try action()
                }
            } else {
                try action()
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

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
        return true
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
        pendingSyncConflict = syncConflictService.prompt()
    }
}
