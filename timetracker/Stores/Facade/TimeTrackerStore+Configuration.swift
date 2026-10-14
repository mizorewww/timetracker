import Foundation
import SwiftData

extension TimeTrackerStore {
    func configureIfNeeded(context: ModelContext) {
        switch startupConfigurationPhase {
        case .completed:
            return
        case .configuring:
            startupConfigurationPhase = .configuring(retryRequested: true)
            return
        case .pending:
            startupConfigurationPhase = .configuring(retryRequested: false)
        }
        defer {
            if case let .configuring(retryRequested) = startupConfigurationPhase {
                startupConfigurationPhase = .pending
                if retryRequested {
                    configureIfNeeded(context: context)
                }
            }
        }
        persistenceWriteSafety = writeAuthorization.usesApplicationState
            ? AppCloudSync.persistenceWriteSafety
            : .ready
        guard persistenceWriteSafety == .ready else { return }
        configureRepositoriesIfNeeded(context: context)
        guard taskRepository != nil else { return }
        if writeAuthorization.usesApplicationState {
            installSyncObservers()
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
        do {
            try context.withHistoryAuthor(.bootstrapMaintenance) {
                try AppleHealthCatalogCleanup.removeLegacyCatalogRowsIfNeeded(context: context)
            }
        } catch {
            startupErrors.append(error)
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
        startupConfigurationPhase = .completed
        enqueueCommittedMutationSystemProjections(
            events: [.fullSync],
            // A Watch command can have a terminal outcome without creating
            // SwiftData history (duplicate, missing, invalid, or failed).
            // Re-publish current state at startup so that forced-only work
            // interrupted by process exit still converges.
            forcedSystemSinks: [.watch]
        )
        if writeAuthorization.usesApplicationState,
           AppRuntimeEnvironment.isUnitTestHost() == false
        {
            Task {
                await refreshCloudAccountStatus()
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
