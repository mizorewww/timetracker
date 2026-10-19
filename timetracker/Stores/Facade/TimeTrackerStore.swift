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
    let taskDraftRecoveryController: TaskDraftRecoveryController
    @ObservationIgnored
    let committedMutationSystemProjectionScheduler:
        CommittedMutationSystemProjectionScheduler?

    init(
        llmCredentialStore: (any LLMCredentialStoring)? = nil,
        inboxSuggestionService: LLMInboxSuggestionService? = nil,
        checklistVisualSuggestionService: LLMChecklistVisualSuggestionService? = nil,
        writeAuthorization: StoreWriteAuthorization = .applicationState,
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
        self.writeAuthorization = writeAuthorization
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
    }

    /// Domain-store passthroughs: the facade keeps no array copies of its own.
    /// Reads forward to the owning domain store, so Observation tracks the
    /// domain store property as the dependency; refresh functions rebuild the
    /// derived facade indexes explicitly (see TimeTrackerStore+DomainRefreshes).
    var tasks: [TaskNode] {
        taskDomainStore.tasks
    }

    var taskCategories: [TaskCategory] {
        taskDomainStore.categories
    }

    var taskCategoryAssignments: [TaskCategoryAssignment] {
        taskDomainStore.categoryAssignments
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
    var syncedPreferences: [SyncedPreference] {
        preferenceDomainStore.syncedPreferences
    }

    var checklistItems: [ChecklistItem] {
        checklistDomainStore.items
    }

    var checklistItemVisuals: [ChecklistItemVisual] {
        checklistDomainStore.visuals
    }

    var inboxItems: [InboxItem] {
        inboxDomainStore.items
    }

    var inboxSuggestions: [InboxSuggestion] {
        inboxDomainStore.suggestions
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

    /// Preference passthrough. The setter forwards the device-local optimistic
    /// mutations in Cloud/LLM preference commands to the domain store, keeping
    /// a single owner; the next preference refresh overwrites it either way.
    var preferences: AppPreferences {
        get { preferenceDomainStore.preferences }
        set { preferenceDomainStore.preferences = newValue }
    }

    var persistenceWriteSafety = AppCloudSync.persistenceWriteSafety
    var effectivePersistenceWriteSafety: PersistenceWriteSafety {
        guard writeAuthorization.usesApplicationState else { return .ready }
        let applicationSafety = AppCloudSync.persistenceWriteSafety
        return applicationSafety == .ready ? persistenceWriteSafety : applicationSafety
    }

    var rollupDomainStore = RollupStore()
    /// Pure memo of analytics snapshots and day buckets. Readers key on
    /// `analyticsRevision`, which every invalidation bumps, so filling the
    /// memo from a view's `body` must not itself publish a change.
    @ObservationIgnored var analyticsDomainStore = AnalyticsStore()
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
    /// Today page read-model cache; see Features/Home/HomeReadModels.swift.
    @ObservationIgnored var todayHomeContentCache:
        (key: TodayHomeContentCacheKey, content: TodayHomeContent)?
    /// Today metrics cache; see Features/Home/HomeReadModels.swift. Keyed by
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
    /// `configureIfNeeded` can be re-entered by a refresh it triggers; a
    /// re-entrant call only requests one more pass after the current one.
    enum StartupConfigurationPhase {
        case pending
        case configuring(retryRequested: Bool)
        case completed
    }

    @ObservationIgnored var startupConfigurationPhase = StartupConfigurationPhase.pending

    var hasCompletedStartupConfiguration: Bool {
        if case .completed = startupConfigurationPhase {
            true
        } else {
            false
        }
    }

    enum DesktopDestination: String, CaseIterable, Identifiable {
        case today = "Today"
        case inbox = "Inbox"
        case tasks = "Tasks"
        case pomodoro = "Pomodoro"
        case analytics = "Analytics"

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
            }
        }

        var symbolName: String {
            switch self {
            case .today: "sun.max"
            case .inbox: "tray"
            case .tasks: "checklist"
            case .pomodoro: "timer"
            case .analytics: "chart.bar"
            }
        }
    }

    var modelContext: ModelContext?
    var taskRepository: SwiftDataTaskRepository?
    var timeRepository: SwiftDataTimeTrackingRepository?
    var pomodoroRepository: SwiftDataPomodoroRepository?
    var taskDomainStore = TaskStore()
    var ledgerDomainStore = LedgerStore()
    var checklistDomainStore = ChecklistStore()
    var inboxDomainStore = InboxStore()
    var preferenceDomainStore = PreferenceStore()
    var syncObservers: [SyncNotificationObserverToken] = []
    @ObservationIgnored var storeMutationObserver: SyncNotificationObserverToken?
    var taskCategoryByID: [UUID: TaskCategory] = [:]
    var taskCategoryIDByRootTaskID: [UUID: UUID] = [:]
    var taskCategoryAssignmentByRootTaskID: [UUID: TaskCategoryAssignment] = [:]
    var forecastEligibleTaskIDCache: Set<UUID> = []
    /// Single owner of the task lookups (`taskByID`, `childrenByParentID`,
    /// paths); the facade exposes them as read-through properties.
    var taskTreeIndexes = TaskTreeIndexes.empty
    var taskTreeReadIndex = TaskTreeReadIndex.empty
    @ObservationIgnored var taskTreeReadIndexRevision: UInt64 = 0
    var taskReadModelRevision: UInt64 = 0
    @ObservationIgnored var todayHeatmapRecurrenceProjection =
        TodayHeatmapRecurrenceProjection.empty
    @ObservationIgnored var taskTreeProjectionCache = TaskTreeProjectionCache()
    var visibleTaskIDs: Set<UUID> = []
    var parentEligibleTaskIDs: Set<UUID> = []
    var trackableTaskIDs: Set<UUID> = []
    var activeSegmentByTaskID: [UUID: TimeSegment] = [:]
    var sortedTodaySegments: [TimeSegment] = []
    @ObservationIgnored var readableLedgerSegmentIDs: Set<UUID> = []
    /// Inputs `readableLedgerSegmentIDs` was last derived from.
    @ObservationIgnored var ledgerRelationshipVisibilityKey:
        (ledgerRevision: UInt64, existingTaskIDs: Set<UUID>)?
    @ObservationIgnored var existingTaskIDs: Set<UUID> = []
    @ObservationIgnored var trackableTasksCache: (revision: UInt64, tasks: [TaskNode])?
    var inboxSuggestionByItemID: [UUID: InboxSuggestion] = [:]
    var inboxItemReadModelByItemID: [UUID: InboxItemReadModel] = [:]
    @ObservationIgnored var scheduledSyncRefreshTask: Task<Void, Never>?
    @ObservationIgnored var pendingSyncActivityReason: SyncRefreshReason?
    @ObservationIgnored let remoteChangeHistory = RemoteChangeHistoryCursor()
}
