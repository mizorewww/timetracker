import Combine
import CoreData
import Foundation
import SwiftData

@MainActor
final class TimeTrackerStore: ObservableObject {
    @Published var tasks: [TaskNode] = [] {
        didSet {
            rebuildTaskIndexes()
        }
    }
    @Published var activeSegments: [TimeSegment] = []
    @Published var todaySegments: [TimeSegment] = [] {
        didSet {
            sortedTodaySegments = todaySegments.sorted { $0.startedAt > $1.startedAt }
        }
    }
    @Published var allSegments: [TimeSegment] = []
    @Published var sessions: [TimeSession] = []
    @Published var pausedSessions: [TimeSession] = []
    @Published var pomodoroRuns: [PomodoroRun] = []
    @Published var countdownEvents: [CountdownEvent] = []
    @Published var syncedPreferences: [SyncedPreference] = []
    @Published var checklistItems: [ChecklistItem] = [] {
        didSet {
            rebuildChecklistIndexes()
        }
    }
    @Published var preferences = AppPreferences.defaults
    @Published var rollupDomainStore = RollupStore()
    @Published var analyticsDomainStore = AnalyticsStore()
    @Published var selectedTaskID: UUID?
    @Published var selectedRange: RangePreset = .today
    @Published var errorMessage: String?
    @Published var taskEditorDraft: TaskEditorDraft?
    @Published var manualTimeDraft: ManualTimeDraft?
    @Published var segmentEditorDraft: SegmentEditorDraft?
    @Published var desktopDestination: DesktopDestination = .today
    @Published var selectedTaskPulseID: UUID?
    @Published var selectedTaskPulseToken = UUID()
    @Published var cloudAccountStatus: String = AppCloudSync.accountStatus

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
        case tasks = "Tasks"
        case pomodoro = "Pomodoro"
        case analytics = "Analytics"
        case settings = "Settings"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return AppStrings.today
            case .tasks: return AppStrings.tasks
            case .pomodoro: return AppStrings.pomodoro
            case .analytics: return AppStrings.analytics
            case .settings: return AppStrings.settings
            }
        }

        var symbolName: String {
            switch self {
            case .today: return "sun.max"
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
    let ledgerSummaryService = LedgerSummaryService()
    let checklistDraftService = ChecklistDraftService()
    let forecastDisplayService = ForecastDisplayService()
    let databaseMaintenanceService = DatabaseMaintenanceService()
    let csvExportService = CSVExportService()
    let refreshPlanner = StoreRefreshPlanner()
    let timerCommandHandler = TimerCommandHandler()
    let taskDraftCommandHandler = TaskDraftCommandHandler()
    let pomodoroCommandHandler = PomodoroCommandHandler()
    let ledgerCommandHandler = LedgerCommandHandler()
    let countdownCommandHandler = CountdownCommandHandler()
    let checklistCommandHandler = ChecklistCommandHandler()
    let preferenceCommandHandler = PreferenceCommandHandler()
    let refreshCoordinator = StoreRefreshCoordinator()
    var taskDomainStore = TaskStore()
    var ledgerDomainStore = LedgerStore()
    var preferenceDomainStore = PreferenceStore()
    var syncObservers: [NSObjectProtocol] = []
    var taskByID: [UUID: TaskNode] = [:]
    var childrenByParentID: [UUID?: [TaskNode]] = [:]
    var checklistByTaskID: [UUID: [ChecklistItem]] = [:]
    var taskPathByID: [UUID: String] = [:]
    var taskParentPathByID: [UUID: String] = [:]
    var sortedTodaySegments: [TimeSegment] = []
    var scheduledSyncRefreshTask: Task<Void, Never>?
}
