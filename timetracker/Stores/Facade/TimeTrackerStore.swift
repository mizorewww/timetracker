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
    let writeAuthorization: StoreWriteAuthorization

    init(
        llmCredentialStore: (any LLMCredentialStoring)? = nil,
        inboxSuggestionService: LLMInboxSuggestionService? = nil,
        checklistVisualSuggestionService: LLMChecklistVisualSuggestionService? = nil,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
        syncConflictService: SyncConflictService? = nil
    ) {
        self.llmCredentialStore = llmCredentialStore ?? KeychainLLMCredentialStore()
        self.inboxSuggestionService = inboxSuggestionService ?? LLMInboxSuggestionService()
        self.checklistVisualSuggestionService =
            checklistVisualSuggestionService ?? LLMChecklistVisualSuggestionService()
        self.writeAuthorization = writeAuthorization
        self.syncConflictService = syncConflictService ?? SyncConflictService()
    }

    deinit {
        pomodoroReconciliationTask?.cancel()
        scheduledSyncRefreshTask?.cancel()
        for request in inboxSuggestionTasksByItemID.values {
            request.task.cancel()
        }
        for request in checklistVisualSuggestionTasksByItemID.values {
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
    var preferences = AppPreferences.defaults
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
    var selectedRange: RangePreset = .today
    var errorMessage: String?
    var desktopDestination: DesktopDestination = .today
    var tasksRoute: TasksRoute?
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

    enum RangePreset: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "Week"
        case month = "Month"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .today:
                return AppStrings.localized("analytics.range.today")
            case .week:
                return AppStrings.localized("analytics.range.week")
            case .month:
                return AppStrings.localized("analytics.range.month")
            }
        }
    }

    enum DesktopDestination: String, CaseIterable, Identifiable {
        case today = "Today"
        case inbox = "Inbox"
        case tasks = "Tasks"
        case pomodoro = "Pomodoro"
        case analytics = "Analytics"
        case settings = "Settings"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return AppStrings.today
            case .inbox: return AppStrings.inbox
            case .tasks: return AppStrings.tasks
            case .pomodoro: return AppStrings.focus
            case .analytics: return AppStrings.analytics
            case .settings: return AppStrings.settings
            }
        }

        var symbolName: String {
            switch self {
            case .today: return "sun.max"
            case .inbox: return "tray"
            case .tasks: return "checklist"
            case .pomodoro: return "timer"
            case .analytics: return "chart.bar"
            case .settings: return "gearshape"
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
    let taskDraftCommandHandler = TaskDraftCommandHandler()
    let pomodoroCommandHandler = PomodoroCommandHandler()
    let ledgerCommandHandler = LedgerCommandHandler()
    let countdownCommandHandler = CountdownCommandHandler()
    let checklistCommandHandler = ChecklistCommandHandler()
    let inboxCommandHandler = InboxCommandHandler()
    let preferenceCommandHandler = PreferenceCommandHandler()
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
    @ObservationIgnored var systemActionMutationObserver: SyncNotificationObserverToken?
    var taskByID: [UUID: TaskNode] = [:]
    var taskCategoryByID: [UUID: TaskCategory] = [:]
    var taskCategoryIDByRootTaskID: [UUID: UUID] = [:]
    var taskCategoryAssignmentByRootTaskID: [UUID: TaskCategoryAssignment] = [:]
    var forecastEligibleTaskIDCache: Set<UUID> = []
    @ObservationIgnored var taskTreeIndexes = TaskTreeIndexes.empty
    var childrenByParentID: [UUID?: [TaskNode]] = [:]
    var taskTreeReadIndex = TaskTreeReadIndex.empty
    @ObservationIgnored var taskTreeReadIndexRevision: UInt64 = 0
    @ObservationIgnored var taskTreeProjectionCache = TaskTreeProjectionCache()
    var checklistByTaskID: [UUID: [ChecklistItem]] = [:]
    var taskPathByID: [UUID: String] = [:]
    var taskParentPathByID: [UUID: String] = [:]
    var visibleTaskIDs: Set<UUID> = []
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
