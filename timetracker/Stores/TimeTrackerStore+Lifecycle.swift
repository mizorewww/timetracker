import CoreData
import Foundation
import SwiftData

extension TimeTrackerStore {
    func configureIfNeeded(context: ModelContext) {
        guard taskRepository == nil else { return }
        self.modelContext = context
        let taskRepository = SwiftDataTaskRepository(context: context)
        let timeRepository = SwiftDataTimeTrackingRepository(context: context)
        self.taskRepository = taskRepository
        self.timeRepository = timeRepository
        self.pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository)
        installSyncObservers()

        do {
            try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(context: context)
            try migrateLegacyCountdownEventsIfNeeded(context: context)
            try SeedData.ensureSeeded(context: context)
            try refresh()
            Task {
                await refreshCloudAccountStatus()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshQuietly() {
        do {
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshForForeground() async {
        refreshQuietly()
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
    }


    func refresh() throws {
        try refresh(plan: refreshPlanner.plan(after: [.fullSync]))
    }

    private func refresh(plan: StoreRefreshPlan) throws {
        guard taskRepository != nil, timeRepository != nil else { return }

        if plan.refreshTasks {
            try refreshTaskDomain()
        }
        if plan.refreshLedger {
            try refreshLedgerDomain(includeHistory: plan.includeLedgerHistory)
        }
        if plan.refreshPomodoro {
            try refreshPomodoroDomain()
        }
        if plan.refreshPreferences {
            try refreshPreferenceDomain()
        }
        if plan.refreshCountdown {
            countdownEvents = try fetchCountdownEvents()
        }
        if plan.refreshChecklist {
            checklistItems = try fetchChecklistItems()
        }
        if plan.refreshRollups {
            refreshRollupDomain()
        }
        if plan.refreshAnalytics {
            refreshAnalyticsDomain()
        }

        if plan.validateSelection {
            validateSelectedTask()
        }

        if plan.syncLiveActivities {
            syncLiveActivitiesIfAvailable()
        }
    }

    private func validateSelectedTask() {
        if selectedTaskID == nil {
            selectedTaskID = activeSegments.first?.taskID ?? tasks.first?.id
        } else if let selectedTaskID, taskByID[selectedTaskID] == nil {
            self.selectedTaskID = activeSegments.first?.taskID ?? tasks.first?.id
        }
    }

    private func refreshTaskDomain() throws {
        guard let taskRepository else { return }
        try taskDomainStore.refresh(repository: taskRepository)
        tasks = taskDomainStore.tasks
    }

    private func refreshLedgerDomain(includeHistory: Bool) throws {
        guard let timeRepository else { return }
        if includeHistory {
            try ledgerDomainStore.refresh(repository: timeRepository)
        } else {
            try ledgerDomainStore.refreshVisible(repository: timeRepository)
        }
        activeSegments = ledgerDomainStore.activeSegments
        pausedSessions = ledgerDomainStore.pausedSessions
        allSegments = ledgerDomainStore.allSegments
        sessions = ledgerDomainStore.sessions
        todaySegments = ledgerDomainStore.todaySegments
    }

    private func refreshPomodoroDomain() throws {
        pomodoroRuns = try pomodoroRepository?.runs() ?? []
    }

    private func refreshPreferenceDomain() throws {
        preferenceDomainStore.refresh(syncedPreferences: try fetchSyncedPreferences())
        syncedPreferences = preferenceDomainStore.syncedPreferences
        preferences = preferenceDomainStore.preferences
    }

    private func refreshRollupDomain() {
        var store = rollupDomainStore
        store.refresh(
            tasks: tasks,
            segments: allSegments,
            checklistItems: checklistItems,
            now: Date()
        )
        rollupDomainStore = store
    }

    private func refreshAnalyticsDomain() {
        refreshCachedAnalyticsSnapshots(now: Date())
    }

    @discardableResult
    func perform(event: StoreDomainEvent = .fullSync, _ action: () throws -> Void) -> Bool {
        perform(events: [event], action)
    }

    @discardableResult
    func perform(events: Set<StoreDomainEvent>, _ action: () throws -> Void) -> Bool {
        do {
            try action()
            try refresh(plan: refreshPlanner.plan(after: events))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func installSyncObservers() {
        guard syncObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            .NSPersistentStoreRemoteChange,
            NSPersistentCloudKitContainer.eventChangedNotification
        ]
        syncObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let store = self else { return }
                Task { @MainActor in
                    store.scheduleQuietRefresh()
                }
            }
        }
    }

    private func scheduleQuietRefresh() {
        scheduledSyncRefreshTask?.cancel()
        scheduledSyncRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            do {
                try refresh(plan: refreshPlanner.plan(after: [.remoteImportCompleted]))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }


    private func fetchSyncedPreferences() throws -> [SyncedPreference] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<SyncedPreference>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.key),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        let all = try modelContext.fetch(descriptor)
        return SyncedPreferenceService.latestByKey(all)
            .values
            .sorted { $0.key < $1.key }
    }

    private func fetchChecklistItems() throws -> [ChecklistItem] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<ChecklistItem>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.taskID),
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchCountdownEvents() throws -> [CountdownEvent] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<CountdownEvent>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [
                SortDescriptor(\.date),
                SortDescriptor(\.createdAt)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    private func migrateLegacyCountdownEventsIfNeeded(context: ModelContext) throws {
        guard !UserDefaults.standard.bool(forKey: "CountdownEventsMigratedToSwiftData"),
              let json = UserDefaults.standard.string(forKey: "CountdownEventsJSON") else {
            return
        }

        let existing = try context.fetch(FetchDescriptor<CountdownEvent>())
        guard existing.isEmpty else {
            UserDefaults.standard.set(true, forKey: "CountdownEventsMigratedToSwiftData")
            return
        }

        for legacy in LegacyCountdownEvent.decode(json) {
            context.insert(
                CountdownEvent(
                    title: legacy.title,
                    date: legacy.date,
                    deviceID: DeviceIdentity.current
                )
            )
        }
        try context.save()
        UserDefaults.standard.set(true, forKey: "CountdownEventsMigratedToSwiftData")
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

        var errorDescription: String? {
            "TimeTrackerStore has not been configured with a ModelContext."
        }
    }
}

private struct LegacyCountdownEvent: Codable {
    var title: String
    var date: Date

    static func decode(_ json: String) -> [LegacyCountdownEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = json.data(using: .utf8),
              let events = try? decoder.decode([LegacyCountdownEvent].self, from: data) else {
            return []
        }
        return events.sorted { $0.date < $1.date }
    }
}
