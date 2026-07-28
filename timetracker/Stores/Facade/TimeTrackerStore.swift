import CoreData
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TimeTrackerStore {
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
        taskDraftRecoveryStore: TaskDraftRecoveryStore? = nil,
        committedMutationSystemProjectionScheduler:
        CommittedMutationSystemProjectionScheduler? = nil
    ) {
        self.llmCredentialStore =
            llmCredentialStore ?? Self.defaultLLMCredentialStore()
        self.inboxSuggestionService = inboxSuggestionService ?? LLMInboxSuggestionService()
        self.checklistVisualSuggestionService =
            checklistVisualSuggestionService ??
            Self.defaultChecklistVisualSuggestionService()
        let resolvedAppleHealthReader =
            appleHealthDataReader ?? AppleHealthDataReaderFactory.platformDefault()
        let resolvedAppleHealthPreferences =
            appleHealthTimelinePreferenceStore
                ?? Self.defaultAppleHealthTimelinePreferenceStore()
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
        self.syncConflictService = syncConflictService ?? Self.defaultSyncConflictService()
        taskDraftRecoveryController = TaskDraftRecoveryController(
            store: taskDraftRecoveryStore ?? TaskDraftRecoveryStore()
        )
        self.committedMutationSystemProjectionScheduler =
            committedMutationSystemProjectionScheduler
    }

    private static func defaultAppleHealthTimelinePreferenceStore()
        -> any AppleHealthTimelinePreferenceStoring
    {
        #if DEBUG && os(iOS)
        if let fixture =
            UITestAppleHealthDataReader.preferenceStoreIfRequested()
        {
            return fixture
        }
        #endif
        return UserDefaultsAppleHealthTimelinePreferenceStore()
    }

    private static func defaultLLMCredentialStore()
        -> any LLMCredentialStoring
    {
        #if DEBUG
        if CommandLine.arguments.contains("--uitesting"),
           CommandLine.arguments.contains("--uitesting-live-llm") ||
           CommandLine.arguments.contains(
               UITestChecklistVisualSuggestionFixture.enableArgument
           )
        {
            return UITestLLMCredentialStore()
        }
        #endif
        return KeychainLLMCredentialStore()
    }

    private static func defaultChecklistVisualSuggestionService()
        -> LLMChecklistVisualSuggestionService
    {
        #if DEBUG
        if let fixture =
            UITestChecklistVisualSuggestionFixture.serviceIfRequested()
        {
            return fixture
        }
        #endif
        return LLMChecklistVisualSuggestionService()
    }

    deinit {
        pomodoroReconciliationTask?.cancel()
        scheduledSyncRefreshTask?.cancel()
        appleHealthTimelineLoadTask?.cancel()
        for request in inboxSuggestionTasksByItemID.values {
            request.task.cancel()
        }
        for request in checklistVisualSuggestionTasksByItemID.values {
            request.task.cancel()
        }
        for request in checklistVisualSuggestionDebounceTasksByItemID.values {
            request.task.cancel()
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

    var inboxSuggestionInFlightIDs: Set<UUID> = []
    var inboxSuggestionFailureByItemID: [UUID: String] = [:]
    @ObservationIgnored var inboxSuggestionPendingIDs: [UUID] = []
    @ObservationIgnored var inboxSuggestionPendingShowsErrors: Set<UUID> = []
    @ObservationIgnored var inboxSuggestionTasksByItemID: [UUID: StoreLLMSuggestionTask] = [:]
    var checklistVisualSuggestionInFlightIDs: Set<UUID> = []
    @ObservationIgnored var checklistVisualSuggestionFailureFingerprintByItemID: [UUID: String] = [:]
    @ObservationIgnored var checklistVisualSuggestionRetryAfterByItemID: [UUID: Date] = [:]
    @ObservationIgnored var checklistVisualSuggestionTasksByItemID: [UUID: StoreLLMSuggestionTask] = [:]
    @ObservationIgnored var checklistVisualSuggestionSchedulingFingerprintByItemID: [UUID: String] = [:]
    @ObservationIgnored var checklistVisualSuggestionDebounceTasksByItemID:
        [UUID: StoreChecklistVisualSuggestionDebounceTask] = [:]
    var preferences = AppPreferences.defaults
    var isAppleHealthTimelineEnabled: Bool
    var appleHealthTimelineItems: [AppleHealthTimelineItem] = []
    var appleHealthTimelineState: AppleHealthTimelineState
    var appleHealthTaskCatalogErrorMessage: String?
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
    var selectedTaskID: UUID?
    var errorMessage: String?
    var desktopDestination: DesktopDestination = .today
    var tasksRoute: TasksRoute?
    @ObservationIgnored let taskDetailNavigationGuard = TaskDetailNavigationGuard()
    var selectedTaskPulseID: UUID?
    var selectedTaskPulseToken = UUID()
    var cloudAccountCheck: CloudAccountCheckOutcome?
    @ObservationIgnored var cloudAccountCheckRequestID: UUID?
    var lastSyncActivity: SyncActivityOutcome?
    var pendingSyncConflict: SyncConflictPrompt?
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
    var taskRepository: TaskRepository?
    var timeRepository: TimeTrackingRepository?
    var pomodoroRepository: PomodoroRepository?
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
