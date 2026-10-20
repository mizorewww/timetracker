import Foundation
import SwiftData

extension TimeTrackerStore {
    /// Throws the first startup step failure (after every step has run) so the
    /// scene that started configuration can present it.
    func configureIfNeeded(context: ModelContext) throws {
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
                    do {
                        try configureIfNeeded(context: context)
                    } catch {
                        logUnpresentedFailure("Startup configuration retry", error)
                    }
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
        #if DEBUG
        do {
            try context.withHistoryAuthor(.bootstrapMaintenance) {
                try SeedData.ensureSeeded(context: context)
            }
        } catch {
            startupErrors.append(error)
        }
        #endif
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
        startupConfigurationPhase = .completed
        // `.fullSync` republishes every system surface, including the Watch
        // state a terminal Watch command outcome may not have recorded.
        enqueueCommittedMutationSystemProjections(events: [.fullSync])
        if writeAuthorization.usesApplicationState, AppCloudSync.checksCloudAccountAutomatically {
            Task {
                await refreshCloudAccountStatus()
            }
        }
        if let firstError = startupErrors.first {
            throw firstError
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
