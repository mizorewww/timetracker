import Foundation
import SwiftData

extension TimeTrackerStore {
    static func defaultSyncConflictService() -> SyncConflictService {
        guard CommandLine.arguments.contains("--uitesting") else {
            return SyncConflictService()
        }
        let stateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeTrackerUITests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(SyncConflictService.stateFileName)
        return SyncConflictService(stateURL: stateURL)
    }

    func configureIfNeeded(context: ModelContext) {
        guard hasCompletedStartupConfiguration == false else { return }
        guard isConfiguringStartup == false else {
            shouldRetryStartupConfiguration = true
            return
        }
        isConfiguringStartup = true
        defer {
            isConfiguringStartup = false
            if shouldRetryStartupConfiguration {
                shouldRetryStartupConfiguration = false
                configureIfNeeded(context: context)
            }
        }
        if writeAuthorization.usesApplicationState {
            persistenceWriteSafety = AppCloudSync.persistenceWriteSafety
            guard AppCloudSync.allowsUserWrites || AppCloudSync.isCloudRecoveryPending else {
                return
            }
        } else {
            persistenceWriteSafety = .ready
        }
        let configuresSyncConflictState = writeAuthorization.usesApplicationState ||
            syncConflictService.stateURLOverride != nil
        let isCloudRecoveryPending = writeAuthorization.usesApplicationState &&
            AppCloudSync.isCloudRecoveryPending
        if isCloudRecoveryPending == false,
           configuresSyncConflictState,
           pendingSyncConflict == nil
        {
            do {
                try replacePendingSyncConflict(
                    syncConflictService.prompt()
                )
            } catch {
                let detail = error.localizedDescription
                persistenceWriteSafety = .cloudRecoveryPending(detail)
                errorMessage = detail
                return
            }
        }

        // Keep facade commands unavailable until the authoritative conflict
        // state has been read successfully. A failed prompt read must not let
        // migrations, seeding, or a direct command race the recovery barrier.
        configureRepositoriesIfNeeded(context: context)
        guard taskRepository != nil else { return }
        if writeAuthorization.usesApplicationState {
            installSyncObservers()
        }

        if isCloudRecoveryPending {
            configureCloudRecovery(context: context)
            return
        }
        if pendingSyncConflict != nil {
            configureCloudRecovery(context: context)
            return
        }

        var startupErrors: [Error] = []
        do {
            try context.withHistoryAuthor(.bootstrapMaintenance) {
                try SyncedPreferenceService.migrateSensitivePreferences(
                    context: context,
                    credentialStore: llmCredentialStore
                )
            }
        } catch {
            startupErrors.append(error)
        }
        do {
            try context.withHistoryAuthor(.bootstrapMaintenance) {
                try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(context: context)
            }
        } catch {
            startupErrors.append(error)
        }
        do {
            try context.withHistoryAuthor(.bootstrapMaintenance) {
                try migrateLegacyCountdownEventsIfNeeded(context: context)
            }
        } catch {
            startupErrors.append(error)
        }
        do {
            try context.withHistoryAuthor(.bootstrapMaintenance) {
                try SeedData.ensureSeeded(context: context)
            }
        } catch {
            startupErrors.append(error)
        }
        if configuresSyncConflictState {
            bootstrapSyncConflictStateIfNeeded(
                context: context,
                startupErrors: &startupErrors
            )
        }
        do {
            try refresh()
        } catch {
            startupErrors.append(error)
        }
        reconcileActivePomodoro(now: Date())
        if let firstError = startupErrors.first {
            errorMessage = firstError.localizedDescription
        }
        hasCompletedStartupConfiguration = true
        persistenceWriteSafety = writeAuthorization.usesApplicationState
            ? AppCloudSync.persistenceWriteSafety
            : .ready
        enqueueCommittedMutationSystemProjections(
            events: [.fullSync],
            // A Watch command can have a terminal outcome without creating
            // SwiftData history (duplicate, missing, invalid, or failed).
            // Re-publish current state at startup so that forced-only work
            // interrupted by process exit still converges.
            forcedSystemSinks: [.watch]
        )
        if writeAuthorization.usesApplicationState,
           timetrackerApp.isUnitTestHost() == false
        {
            Task {
                await refreshCloudAccountStatus()
            }
        }
    }

    /// Installs only the read-side synchronization pipeline while a protected
    /// local branch is being compared with the freshly imported CloudKit store.
    /// Migrations, seeding, and other startup writes wait until reconciliation
    /// has either matched the branches or produced a user-visible conflict.
    private func configureCloudRecovery(context: ModelContext) {
        var startupErrors: [Error] = []
        bootstrapSyncConflictStateIfNeeded(
            context: context,
            startupErrors: &startupErrors
        )
        do {
            try refreshCoordinator.refreshReadModels(
                self,
                plan: refreshPlanner.plan(after: [.fullSync])
            )
        } catch {
            startupErrors.append(error)
        }
        persistenceWriteSafety = AppCloudSync.persistenceWriteSafety
        if let firstError = startupErrors.first {
            errorMessage = firstError.localizedDescription
        }
        if persistenceWriteSafety == .ready,
           pendingSyncConflict == nil
        {
            configureIfNeeded(context: context)
        }
    }

    /// A corrupt primary state file is quarantined by the first load. Retry
    /// once so bootstrap can recover from the independent protected snapshot,
    /// then remember the successful bootstrap across recovery-to-startup
    /// recursion to avoid restoring an explicit local winner twice.
    private func bootstrapSyncConflictStateIfNeeded(
        context: ModelContext,
        startupErrors: inout [Error]
    ) {
        guard hasBootstrappedSyncConflictState == false else { return }
        for _ in 0 ..< 2 {
            do {
                try replacePendingSyncConflict(
                    syncConflictService.bootstrap(
                        context: context
                    )
                )
                hasBootstrappedSyncConflictState = true
                return
            } catch {
                startupErrors.append(error)
            }
        }
    }

    /// Attaches persistence repositories without running application-startup
    /// migrations, seeding, observers, recovery, or background automations.
    /// Tests and narrowly scoped recovery flows can use this without claiming
    /// that the full application lifecycle has completed.
    func configureRepositoriesIfNeeded(context: ModelContext) {
        guard taskRepository == nil else { return }
        modelContext = context
        let taskRepository = SwiftDataTaskRepository(context: context)
        let timeRepository = SwiftDataTimeTrackingRepository(context: context)
        self.taskRepository = taskRepository
        self.timeRepository = timeRepository
        pomodoroRepository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository
        )
    }
}
