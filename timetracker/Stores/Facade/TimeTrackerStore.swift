import CoreData
import Foundation
import Observation
import SwiftData

@concurrent
private func loadSyncConflictPrompt(
    from service: SyncConflictService
) async throws -> SyncConflictPrompt? {
    try Task.checkCancellation()
    let prompt = try service.prompt()
    try Task.checkCancellation()
    return prompt
}

@MainActor
@Observable
final class TimeTrackerStore {
    typealias SyncConflictPromptLoader =
        @Sendable () async throws -> SyncConflictPrompt?

    let llmCredentialStore: any LLMCredentialStoring
    let inboxSuggestionService: LLMInboxSuggestionService
    let checklistVisualSuggestionService: LLMChecklistVisualSuggestionService
    let appleHealthDataReader: any AppleHealthDataReading
    let appleHealthReplicaRepository: any AppleHealthReplicaRepository
    let appleHealthReplicaSyncService: AppleHealthReplicaSyncService?
    let appleHealthTimelinePreferenceStore: any AppleHealthTimelinePreferenceStoring
    let writeAuthorization: StoreWriteAuthorization
    let taskDraftRecoveryController: TaskDraftRecoveryController
    @ObservationIgnored
    let committedMutationSystemProjectionScheduler:
        CommittedMutationSystemProjectionScheduler?

    init(
        llmCredentialStore: (any LLMCredentialStoring)? = nil,
        inboxSuggestionService: LLMInboxSuggestionService? = nil,
        checklistVisualSuggestionService: LLMChecklistVisualSuggestionService? = nil,
        appleHealthDataReader: (any AppleHealthDataReading)? = nil,
        appleHealthReplicaRepository:
        (any AppleHealthReplicaRepository)? = nil,
        appleHealthTimelinePreferenceStore: (any AppleHealthTimelinePreferenceStoring)? = nil,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        syncConflictService: SyncConflictService? = nil,
        syncConflictPromptLoader: SyncConflictPromptLoader? = nil,
        taskDraftRecoveryStore: TaskDraftRecoveryStore? = nil,
        committedMutationSystemProjectionScheduler:
        CommittedMutationSystemProjectionScheduler? = nil
    ) {
        self.llmCredentialStore =
            llmCredentialStore ?? Self.defaultLLMCredentialStore()
        self.inboxSuggestionService = inboxSuggestionService ?? LLMInboxSuggestionService()
        self.checklistVisualSuggestionService =
            checklistVisualSuggestionService ??
            LLMChecklistVisualSuggestionService()
        let resolvedAppleHealthReader =
            appleHealthDataReader ?? AppleHealthDataReaderFactory.platformDefault()
        let resolvedAppleHealthPreferences =
            appleHealthTimelinePreferenceStore
                ?? UserDefaultsAppleHealthTimelinePreferenceStore()
        let resolvedAppleHealthReplica =
            appleHealthReplicaRepository
                ?? AppleHealthReplicaModelContainerFactory
                .platformDefaultRepository()
        self.appleHealthDataReader = resolvedAppleHealthReader
        self.appleHealthReplicaRepository = resolvedAppleHealthReplica
        if let changeReader =
            resolvedAppleHealthReader
                as? any AppleHealthReplicaChangeReading
        {
            appleHealthReplicaSyncService = AppleHealthReplicaSyncService(
                reader: changeReader,
                repository: resolvedAppleHealthReplica
            )
        } else {
            appleHealthReplicaSyncService = nil
        }
        self.appleHealthTimelinePreferenceStore = resolvedAppleHealthPreferences
        isAppleHealthTimelineEnabled = resolvedAppleHealthPreferences.isTimelineEnabled
        appleHealthTimelineState = if resolvedAppleHealthReader.isHealthDataAvailable {
            resolvedAppleHealthPreferences.isTimelineEnabled ? .ready : .disabled
        } else {
            .unavailable
        }
        self.writeAuthorization = writeAuthorization
        let resolvedSyncConflictService =
            syncConflictService ?? Self.defaultSyncConflictService()
        self.syncConflictService = resolvedSyncConflictService
        if let syncConflictPromptLoader {
            self.syncConflictPromptLoader =
                syncConflictPromptLoader
        } else {
            self.syncConflictPromptLoader = {
                try await loadSyncConflictPrompt(
                    from: resolvedSyncConflictService
                )
            }
        }
        taskDraftRecoveryController = TaskDraftRecoveryController(
            store: taskDraftRecoveryStore ?? TaskDraftRecoveryStore()
        )
        self.committedMutationSystemProjectionScheduler =
            committedMutationSystemProjectionScheduler
    }

    private static func defaultLLMCredentialStore()
        -> any LLMCredentialStoring
    {
        KeychainLLMCredentialStore()
    }

    deinit {
        pomodoroReconciliationTask?.cancel()
        scheduledSyncRefreshTask?.cancel()
        syncConflictPromptRefreshTask?.cancel()
        appleHealthTimelineLoadTask?.cancel()
        appleHealthReplicaObservationSetupTask?.cancel()
        if let observer =
            appleHealthDataReader as? any AppleHealthReplicaChangeObserving
        {
            Task { @MainActor in
                observer.stopObservingReplicaChanges()
            }
        }
    }

    var tasks: [TaskNode] = [] {
        didSet {
            rebuildTaskIndexes()
        }
    }

    var taskCategories: [TaskCategory] = [] {
        didSet {
            rebuildTaskCategoryIndexes()
        }
    }

    var taskCategoryAssignments: [TaskCategoryAssignment] = [] {
        didSet {
            rebuildTaskCategoryIndexes()
        }
    }

    var activeSegments: [TimeSegment] = [] {
        didSet {
            activeSegmentByTaskID = activeSegments.reduce(into: [:]) { result, segment in
                if result[segment.taskID] == nil {
                    result[segment.taskID] = segment
                }
            }
        }
    }

    var todaySegments: [TimeSegment] = [] {
        didSet {
            sortedTodaySegments = todaySegments.sorted { $0.startedAt > $1.startedAt }
        }
    }

    var allSegments: [TimeSegment] = []
    var sessions: [TimeSession] = []
    var pomodoroRuns: [PomodoroRun] = []
    @ObservationIgnored var pomodoroReconciliationTask: Task<Void, Never>?
    var countdownEvents: [CountdownEvent] = []
    var syncedPreferences: [SyncedPreference] = []
    var checklistItems: [ChecklistItem] = [] {
        didSet {
            if !suppressChecklistIndexRebuild {
                rebuildChecklistIndexes()
            }
        }
    }

    var checklistItemVisuals: [ChecklistItemVisual] = [] {
        didSet {
            if !suppressChecklistVisualIndexRebuild {
                rebuildChecklistVisualIndexes()
            }
        }
    }

    var inboxItems: [InboxItem] = [] {
        didSet {
            if !suppressInboxSuggestionIndexRebuild {
                rebuildInboxSuggestionIndexes()
            }
        }
    }

    var inboxSuggestions: [InboxSuggestion] = [] {
        didSet {
            if !suppressInboxSuggestionIndexRebuild {
                rebuildInboxSuggestionIndexes()
            }
        }
    }

    @ObservationIgnored let inboxSuggestionLifecycle =
        LLMSuggestionRequestLifecycle<UUID, String>(maximumConcurrency: 3)
    @ObservationIgnored let checklistVisualSuggestionLifecycle =
        LLMSuggestionRequestLifecycle<UUID, ChecklistVisualSuggestionFailure>(maximumConcurrency: 3)
    @ObservationIgnored var checklistVisualSuggestionSchedulingFingerprintByItemID: [UUID: String] = [:]
    /// Forwarding accessors keep the observable in-flight/failure reads of
    /// inbox commands, read models, and views working through the lifecycle.
    var inboxSuggestionInFlightIDs: Set<UUID> {
        inboxSuggestionLifecycle.inFlightIDs
    }

    var inboxSuggestionFailureByItemID: [UUID: String] {
        get { inboxSuggestionLifecycle.failureByItemID }
        set { inboxSuggestionLifecycle.failureByItemID = newValue }
    }

    var preferences = AppPreferences.defaults
    var isAppleHealthTimelineEnabled: Bool
    var appleHealthTimelineItems: [AppleHealthTimelineItem] = []
    var appleHealthTimelineState: AppleHealthTimelineState
    var appleHealthReplicaRevision = 0
    var appleHealthTaskCatalogErrorMessage: String?
    @ObservationIgnored var isAppleHealthReplicaObservationActive = false
    @ObservationIgnored var appleHealthReplicaObservationSetupID = UUID()
    @ObservationIgnored var appleHealthReplicaObservationSetupTask:
        Task<Void, Never>?
    @ObservationIgnored var appleHealthTimelineRequestID = UUID()
    @ObservationIgnored var appleHealthTimelineLoadTask:
        Task<AppleHealthSampleBatch, Error>?
    var persistenceWriteSafety = AppCloudSync.persistenceWriteSafety
    var effectivePersistenceWriteSafety: PersistenceWriteSafety {
        guard writeAuthorization.usesApplicationState else { return .ready }
        let applicationSafety = AppCloudSync.persistenceWriteSafety
        return applicationSafety == .ready ? persistenceWriteSafety : applicationSafety
    }

    var rollupDomainStore = RollupStore()
    var analyticsDomainStore = AnalyticsStore()
    var analyticsRevision: UInt = 0
    /// Today timeline snapshot cache (see TimeTrackerStore+Timeline.swift).
    /// Keyed by data revisions + day + minute bucket so repeated body
    /// evaluations after unrelated store writes reuse the last projection.
    @ObservationIgnored var todayTimelineSnapshotCache: TodayTimelineSnapshotCache?
    /// Tasks-page row supplement projection cache (recurrence roles +
    /// quantity progress). Keyed by taskReadModelRevision; see
    /// TimeTrackerStore+TaskReadModels.swift.
    @ObservationIgnored var taskManagementRowSupplementProjectionCache:
        (revision: UInt64, projection: TaskManagementRowSupplementProjection)?
    /// Subtree-active-timer index cache; see TimeTrackerStore+TaskReadModels.swift.
    @ObservationIgnored var taskIDsWithActiveTimerInSubtreeCache:
        (taskRevision: UInt64, analyticsRevision: UInt, taskIDs: Set<UUID>)?
    /// Today page read-model cache; see TimeTrackerStore+HomeReadModels.swift.
    @ObservationIgnored var todayHomeContentCache:
        (key: TodayHomeContentCacheKey, content: TodayHomeContent)?
    /// Today metrics cache; see TimeTrackerStore+HomeReadModels.swift. Keyed by
    /// ledger revision + minute bucket so repeated same-minute calls (30 s
    /// tick, static tab-switch renders, both shells) share one interval query.
    @ObservationIgnored var todayMetricsSnapshotCache:
        (key: (revision: UInt, minuteBucket: Int), snapshot: TodayMetricsSnapshot)?
    var selectedTaskID: UUID?
    var errorMessage: String?
    var desktopDestination: DesktopDestination = .today
    var tasksRoute: TasksRoute?
    var todayTaskRoute: TasksRoute?
    @ObservationIgnored let taskDetailNavigationGuard = TaskDetailNavigationGuard()
    var cloudAccountCheck: CloudAccountCheckOutcome?
    @ObservationIgnored var cloudAccountCheckRequestID: UUID?
    var lastSyncActivity: SyncActivityOutcome?
    var pendingSyncConflict: SyncConflictPrompt?
    @ObservationIgnored
    let syncConflictPromptLoader: SyncConflictPromptLoader
    @ObservationIgnored
    var syncConflictPromptRefreshRequestID = UUID()
    @ObservationIgnored
    var isSyncConflictPromptRefreshRequested = false
    @ObservationIgnored
    var syncConflictPromptRefreshTask: Task<Void, Never>?
    @ObservationIgnored var hasCompletedStartupConfiguration = false
    @ObservationIgnored var hasBootstrappedSyncConflictState = false
    @ObservationIgnored var isConfiguringStartup = false
    @ObservationIgnored var shouldRetryStartupConfiguration = false

    enum DesktopDestination: String, CaseIterable, Identifiable {
        case today = "Today"
        case inbox = "Inbox"
        case tasks = "Tasks"
        case pomodoro = "Pomodoro"
        case analytics = "Analytics"
        case settings = "Settings"

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .today: AppStrings.today
            case .inbox: AppStrings.inbox
            case .tasks: AppStrings.tasks
            case .pomodoro: AppStrings.focus
            case .analytics: AppStrings.analytics
            case .settings: AppStrings.settings
            }
        }

        var symbolName: String {
            switch self {
            case .today: "sun.max"
            case .inbox: "tray"
            case .tasks: "checklist"
            case .pomodoro: "timer"
            case .analytics: "chart.bar"
            case .settings: "gearshape"
            }
        }
    }

    var modelContext: ModelContext?
    var taskRepository: SwiftDataTaskRepository?
    var timeRepository: SwiftDataTimeTrackingRepository?
    var pomodoroRepository: SwiftDataPomodoroRepository?
    let aggregationService = TimeAggregationService()
    let analyticsEngine = AnalyticsEngine()
    let taskTreeService = TaskTreeService()
    let taskTrackingAvailabilityService = TaskTrackingAvailabilityService()
    let ledgerSummaryService = LedgerSummaryService()
    let inboxSuggestionStateService = InboxSuggestionStateService()
    let forecastDisplayService = ForecastDisplayService()
    let databaseMaintenanceService = DatabaseMaintenanceService()
    let selectionCoordinator = StoreSelectionCoordinator()
    let refreshPlanner = StoreRefreshPlanner()
    let checklistCommandHandler = ChecklistCommandHandler()
    let inboxCommandHandler = InboxCommandHandler()
    let refreshCoordinator = StoreRefreshCoordinator()
    let syncConflictService: SyncConflictService
    var taskDomainStore = TaskStore()
    var ledgerDomainStore = LedgerStore()
    var checklistDomainStore = ChecklistStore()
    @ObservationIgnored var suppressChecklistIndexRebuild = false
    @ObservationIgnored var suppressChecklistVisualIndexRebuild = false
    @ObservationIgnored var suppressInboxSuggestionIndexRebuild = false
    var inboxDomainStore = InboxStore()
    var preferenceDomainStore = PreferenceStore()
    var syncObservers: [SyncNotificationObserverToken] = []
    @ObservationIgnored var storeMutationObserver: SyncNotificationObserverToken?
    var taskByID: [UUID: TaskNode] = [:]
    var taskCategoryByID: [UUID: TaskCategory] = [:]
    var taskCategoryIDByRootTaskID: [UUID: UUID] = [:]
    var taskCategoryAssignmentByRootTaskID: [UUID: TaskCategoryAssignment] = [:]
    var forecastEligibleTaskIDCache: Set<UUID> = []
    @ObservationIgnored var taskTreeIndexes = TaskTreeIndexes.empty
    var childrenByParentID: [UUID?: [TaskNode]] = [:]
    var taskTreeReadIndex = TaskTreeReadIndex.empty
    @ObservationIgnored var taskTreeReadIndexRevision: UInt64 = 0
    var taskReadModelRevision: UInt64 = 0
    @ObservationIgnored var todayHeatmapRecurrenceProjection =
        TodayHeatmapRecurrenceProjection.empty
    @ObservationIgnored var taskTreeProjectionCache = TaskTreeProjectionCache()
    var checklistByTaskID: [UUID: [ChecklistItem]] = [:]
    var taskPathByID: [UUID: String] = [:]
    var taskParentPathByID: [UUID: String] = [:]
    var visibleTaskIDs: Set<UUID> = []
    var parentEligibleTaskIDs: Set<UUID> = []
    var trackableTaskIDs: Set<UUID> = []
    var activeSegmentByTaskID: [UUID: TimeSegment] = [:]
    var sortedTodaySegments: [TimeSegment] = []
    @ObservationIgnored var readableLedgerSegmentIDs: Set<UUID> = []
    var checklistVisualByItemID: [UUID: ChecklistItemVisual] = [:]
    var inboxSuggestionByItemID: [UUID: InboxSuggestion] = [:]
    var inboxItemReadModelByItemID: [UUID: InboxItemReadModel] = [:]
    @ObservationIgnored var scheduledSyncRefreshTask: Task<Void, Never>?
    var scheduledSyncRefreshBatch: SyncRefreshBatch?
    var completedCloudExportResults: [UUID: Bool] = [:]
}
