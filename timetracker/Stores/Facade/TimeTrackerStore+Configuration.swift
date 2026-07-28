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
        configureRepositoriesIfNeeded(context: context)
        guard taskRepository != nil else { return }
        if writeAuthorization.usesApplicationState {
            installSyncObservers()
        }

        if writeAuthorization.usesApplicationState && AppCloudSync.isCloudRecoveryPending {
            configureCloudRecovery(context: context)
            return
        }
        let configuresSyncConflictState = writeAuthorization.usesApplicationState ||
            syncConflictService.stateURLOverride != nil
        if configuresSyncConflictState,
           pendingSyncConflict == nil
        {
            pendingSyncConflict = try? syncConflictService.prompt()
        }
        if pendingSyncConflict != nil {
            configureCloudRecovery(context: context)
            return
        }

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
                pendingSyncConflict = try syncConflictService.bootstrap(context: context)
                hasBootstrappedSyncConflictState = true
                return
            } catch {
                startupErrors.append(error)
            }
        }
    }

    /// Attaches persistence repositories without running application-startup
    /// migrations, seeding, observers, recovery, or background automations.
    /// System actions use this narrow path after their mutation has committed so
    /// they can refresh Widget, Watch, and Live Activity state while the app is closed.
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

    /// Refreshes only the read models required by external system surfaces.
    /// This intentionally avoids the normal refresh coordinator because task and
    /// preference refreshes there may schedule LLM suggestion work.
    @discardableResult
    func refreshCommittedMutationSurfaceReadModels(
        events: Set<StoreDomainEvent>
    ) throws -> Bool {
        let surfaceEvents = events.filter { event in
            switch event {
            case .taskChanged, .ledgerChanged, .pomodoroChanged, .remoteImportCompleted, .fullSync:
                true
            case .checklistChanged, .preferenceChanged, .countdownChanged, .inboxChanged:
                false
            }
        }
        guard surfaceEvents.isEmpty == false else { return false }

        let eventPlan = StoreRefreshPlanner().plan(after: surfaceEvents)
        let taskPlan = StoreRefreshPlan(
            scopes: [.tasks],
            affectedTaskIDs: eventPlan.affectedTaskIDs,
            directlyAffectedTaskIDs: eventPlan.directlyAffectedTaskIDs,
            explicitlyAffectedAncestorTaskIDs: eventPlan.explicitlyAffectedAncestorTaskIDs
        )
        try refreshTaskDomain(plan: taskPlan)

        let hasLoadedLedgerHistory = ledgerDomainStore.hasLoadedHistory
        let includesLedgerHistory = hasLoadedLedgerHistory == false ||
            eventPlan.includeLedgerHistory
        let ledgerPlan = StoreRefreshPlan(
            scopes: includesLedgerHistory
                ? [.ledgerHistory, .rollups]
                : [.ledgerVisible, .rollups],
            affectedTaskIDs: eventPlan.affectedTaskIDs,
            directlyAffectedTaskIDs: eventPlan.directlyAffectedTaskIDs,
            explicitlyAffectedAncestorTaskIDs: eventPlan.explicitlyAffectedAncestorTaskIDs,
            affectedLedgerRanges: hasLoadedLedgerHistory && eventPlan.includeLedgerHistory
                ? eventPlan.affectedLedgerRanges
                : []
        )
        try refreshLedgerDomain(plan: ledgerPlan)
        refreshRollupDomain(plan: ledgerPlan)

        let currentPreferences = try fetchSyncedPreferences()
        preferenceDomainStore.refresh(
            syncedPreferences: currentPreferences,
            localLLMAPIKey: "",
            localLLMAutomaticSuggestionsEnabled: AppDefaults.shared.bool(
                forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
            )
        )
        syncedPreferences = preferenceDomainStore.syncedPreferences
        preferences = preferenceDomainStore.preferences
        return true
    }

    /// Retained for callers that still perform all post-commit effects inline.
    /// The asynchronous projection worker uses the read-model boundary above,
    /// then publishes each system surface independently.
    func refreshCommittedMutationSurfaces(
        events: Set<StoreDomainEvent>,
        widgetCache: WidgetSnapshotCache? = nil,
        now: Date = Date()
    ) throws -> Error? {
        guard try refreshCommittedMutationSurfaceReadModels(events: events) else {
            return nil
        }

        syncLiveActivitiesIfAvailable()
        let widgetError = syncWidgetSnapshotIfAvailable(now: now, cache: widgetCache)
        syncWatchSnapshotIfAvailable(now: now)
        return widgetError
    }
}
