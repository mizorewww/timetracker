import Foundation
import SwiftData

extension TimeTrackerStore {
    func configureIfNeeded(context: ModelContext) {
        guard taskRepository == nil else { return }
        configureRepositoriesIfNeeded(context: context)
        guard taskRepository != nil else { return }
        installSyncObservers()

        var startupErrors: [Error] = []
        do {
            try SyncedPreferenceService.migrateSensitivePreferences(
                context: context,
                credentialStore: llmCredentialStore
            )
        } catch {
            startupErrors.append(error)
        }
        do {
            try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(context: context)
        } catch {
            startupErrors.append(error)
        }
        do {
            try migrateLegacyCountdownEventsIfNeeded(context: context)
        } catch {
            startupErrors.append(error)
        }
        do {
            try SeedData.ensureSeeded(context: context)
        } catch {
            startupErrors.append(error)
        }
        do {
            pendingSyncConflict = try syncConflictService.bootstrap(context: context)
        } catch {
            startupErrors.append(error)
            do {
                pendingSyncConflict = try syncConflictService.bootstrap(context: context)
            } catch {
                startupErrors.append(error)
            }
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
        Task {
            await refreshCloudAccountStatus()
        }
    }

    /// Attaches persistence repositories without running application-startup
    /// migrations, seeding, observers, recovery, or background automations.
    /// System actions use this narrow path after their mutation has committed so
    /// they can refresh Widget, Watch, and Live Activity state while the app is closed.
    func configureRepositoriesIfNeeded(context: ModelContext) {
        guard taskRepository == nil else { return }
        self.modelContext = context
        let taskRepository = SwiftDataTaskRepository(context: context)
        let timeRepository = SwiftDataTimeTrackingRepository(context: context)
        self.taskRepository = taskRepository
        self.timeRepository = timeRepository
        pomodoroRepository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository
        )
    }

    /// Refreshes only the read models required by external system surfaces.
    /// This intentionally avoids the normal refresh coordinator because task and
    /// preference refreshes there may schedule LLM suggestion work.
    func refreshCommittedMutationSurfaces(
        events: Set<StoreDomainEvent>,
        widgetCache: WidgetSnapshotCache? = nil,
        now: Date = Date()
    ) throws -> Error? {
        let surfaceEvents = events.filter { event in
            switch event {
            case .taskChanged, .ledgerChanged, .pomodoroChanged, .remoteImportCompleted, .fullSync:
                true
            case .checklistChanged, .preferenceChanged, .countdownChanged, .inboxChanged:
                false
            }
        }
        guard surfaceEvents.isEmpty == false else { return nil }

        let taskPlan = StoreRefreshPlan(scopes: [.tasks])
        try refreshTaskDomain(plan: taskPlan)

        let ledgerPlan = StoreRefreshPlan(scopes: [.ledgerVisible])
        try refreshLedgerDomain(plan: ledgerPlan)

        let currentPreferences = try fetchSyncedPreferences()
        preferenceDomainStore.refresh(
            syncedPreferences: currentPreferences,
            localLLMAPIKey: "",
            localLLMAutomaticSuggestionsEnabled: UserDefaults.standard.bool(
                forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
            )
        )
        syncedPreferences = preferenceDomainStore.syncedPreferences
        preferences = preferenceDomainStore.preferences

        syncLiveActivitiesIfAvailable()
        let widgetError = syncWidgetSnapshotIfAvailable(now: now, cache: widgetCache)
        syncWatchSnapshotIfAvailable(now: now)
        return widgetError
    }
}
