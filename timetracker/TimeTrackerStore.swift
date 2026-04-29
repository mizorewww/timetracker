import Combine
import CoreData
import Foundation
import SwiftData

@MainActor
final class TimeTrackerStore: ObservableObject {
    @Published private(set) var tasks: [TaskNode] = [] {
        didSet {
            rebuildTaskIndexes()
        }
    }
    @Published private(set) var activeSegments: [TimeSegment] = []
    @Published private(set) var todaySegments: [TimeSegment] = [] {
        didSet {
            sortedTodaySegments = todaySegments.sorted { $0.startedAt > $1.startedAt }
        }
    }
    @Published private(set) var allSegments: [TimeSegment] = []
    @Published private(set) var sessions: [TimeSession] = []
    @Published private(set) var pomodoroRuns: [PomodoroRun] = []
    @Published private(set) var countdownEvents: [CountdownEvent] = []
    @Published private(set) var syncedPreferences: [SyncedPreference] = []
    @Published private(set) var checklistItems: [ChecklistItem] = [] {
        didSet {
            rebuildChecklistIndexes()
        }
    }
    @Published private(set) var preferences = AppPreferences.defaults
    @Published private(set) var taskRollups: [UUID: TaskRollup] = [:]
    @Published var selectedTaskID: UUID?
    @Published var selectedRange: RangePreset = .today
    @Published var errorMessage: String?
    @Published var taskEditorDraft: TaskEditorDraft?
    @Published var manualTimeDraft: ManualTimeDraft?
    @Published var segmentEditorDraft: SegmentEditorDraft?
    @Published var desktopDestination: DesktopDestination = .today
    @Published private(set) var selectedTaskPulseID: UUID?
    @Published private(set) var selectedTaskPulseToken = UUID()
    @Published private var cloudAccountStatus: String = AppCloudSync.accountStatus

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

    private var modelContext: ModelContext?
    private var taskRepository: TaskRepository?
    private var timeRepository: TimeTrackingRepository?
    private var pomodoroRepository: PomodoroRepository?
    private let aggregationService = TimeAggregationService()
    private let analyticsEngine = AnalyticsEngine()
    private let taskTreeService = TaskTreeService()
    private let ledgerSummaryService = LedgerSummaryService()
    private let checklistDraftService = ChecklistDraftService()
    private var taskDomainStore = TaskStore()
    private var ledgerDomainStore = LedgerStore()
    private var preferenceDomainStore = PreferenceStore()
    private var analyticsDomainStore = AnalyticsStore()
    private var syncObservers: [NSObjectProtocol] = []
    private var taskByID: [UUID: TaskNode] = [:]
    private var childrenByParentID: [UUID?: [TaskNode]] = [:]
    private var checklistByTaskID: [UUID: [ChecklistItem]] = [:]
    private var taskPathByID: [UUID: String] = [:]
    private var taskParentPathByID: [UUID: String] = [:]
    private var sortedTodaySegments: [TimeSegment] = []
    private var scheduledSyncRefreshTask: Task<Void, Never>?
    private let rollupService = TaskRollupService()
    private enum RefreshScope: Hashable {
        case tasks
        case ledger
        case pomodoro
        case preferences
        case countdown
        case checklist
        case analytics
        case liveActivities
    }

    private static let fullRefreshScopes: Set<RefreshScope> = [
        .tasks,
        .ledger,
        .pomodoro,
        .preferences,
        .countdown,
        .checklist,
        .analytics,
        .liveActivities
    ]

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

    func addCountdownEvent() {
        perform(refresh: [.countdown]) {
            guard let modelContext else { throw StoreError.notConfigured }
            let event = CountdownEvent(
                title: AppStrings.localized("task.newEvent"),
                date: Date().addingTimeInterval(30 * 24 * 60 * 60),
                deviceID: DeviceIdentity.current
            )
            modelContext.insert(event)
            try modelContext.save()
        }
    }

    func updateCountdownEvent(_ event: CountdownEvent, title: String? = nil, date: Date? = nil) {
        perform(refresh: [.countdown]) {
            if let title {
                event.title = title
            }
            if let date {
                event.date = date
            }
            event.updatedAt = Date()
            event.clientMutationID = UUID()
            try modelContext?.save()
        }
    }

    func deleteCountdownEvent(_ event: CountdownEvent) {
        perform(refresh: [.countdown]) {
            event.deletedAt = Date()
            event.updatedAt = Date()
            event.clientMutationID = UUID()
            try modelContext?.save()
        }
    }

    func refresh() throws {
        try refresh(scopes: Self.fullRefreshScopes)
    }

    private func refresh(scopes: Set<RefreshScope>) throws {
        guard taskRepository != nil, timeRepository != nil else { return }
        let shouldRefreshAll = scopes == Self.fullRefreshScopes

        if shouldRefreshAll || scopes.contains(.tasks) {
            try refreshTaskDomain()
        }
        if shouldRefreshAll || scopes.contains(.ledger) {
            try refreshLedgerDomain()
        }
        if shouldRefreshAll || scopes.contains(.pomodoro) {
            try refreshPomodoroDomain()
        }
        if shouldRefreshAll || scopes.contains(.preferences) {
            try refreshPreferenceDomain()
        }
        if shouldRefreshAll || scopes.contains(.countdown) {
            countdownEvents = try fetchCountdownEvents()
        }
        if shouldRefreshAll || scopes.contains(.checklist) {
            checklistItems = try fetchChecklistItems()
        }
        if shouldRefreshAll || scopes.contains(.analytics) || scopes.contains(.tasks) || scopes.contains(.ledger) || scopes.contains(.checklist) {
            refreshAnalyticsDomain()
        }

        if selectedTaskID == nil {
            selectedTaskID = activeSegments.first?.taskID ?? tasks.first?.id
        } else if let selectedTaskID, taskByID[selectedTaskID] == nil {
            self.selectedTaskID = activeSegments.first?.taskID ?? tasks.first?.id
        }

        if shouldRefreshAll || scopes.contains(.liveActivities) || scopes.contains(.ledger) || scopes.contains(.tasks) {
            syncLiveActivitiesIfAvailable()
        }
    }

    private func refreshTaskDomain() throws {
        guard let taskRepository else { return }
        try taskDomainStore.refresh(repository: taskRepository)
        tasks = taskDomainStore.tasks
    }

    private func refreshLedgerDomain() throws {
        guard let timeRepository else { return }
        try ledgerDomainStore.refresh(repository: timeRepository)
        activeSegments = ledgerDomainStore.activeSegments
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

    private func refreshAnalyticsDomain() {
        taskRollups = analyticsDomainStore.rollups(
            tasks: tasks,
            segments: allSegments,
            checklistItems: checklistItems,
            now: Date()
        )
    }

    func startSelectedTask() {
        guard let selectedTaskID else { return }
        startTask(taskID: selectedTaskID)
    }

    func selectTask(_ taskID: UUID, revealInToday: Bool = true) {
        selectedTaskID = taskID
        if revealInToday {
            desktopDestination = .today
        }
        selectedTaskPulseID = taskID
        selectedTaskPulseToken = UUID()
    }

    func startTask(_ task: TaskNode) {
        selectTask(task.id, revealInToday: false)
        startTask(taskID: task.id)
    }

    private func startTask(taskID: UUID) {
        perform(refresh: [.ledger, .pomodoro, .analytics, .liveActivities]) {
            if activeSegment(for: taskID) != nil {
                return
            }
            if !preferences.allowParallelTimers {
                try pauseOtherActiveSegments(excluding: taskID)
            }
            if let pausedSession = pausedSession(for: taskID) {
                _ = try ResumeSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: pausedSession.id)
                try resumePomodoroIfNeeded(sessionID: pausedSession.id)
                return
            }
            _ = try StartTaskUseCase(repository: requiredTimeRepository()).execute(taskID: taskID, source: .timer)
        }
    }

    private func pauseOtherActiveSegments(excluding taskID: UUID) throws {
        for segment in activeSegments where segment.taskID != taskID {
            try PauseSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: segment.sessionID)
            try interruptPomodoroIfNeeded(sessionID: segment.sessionID)
        }
    }

    func stop(segment: TimeSegment) {
        perform(refresh: [.ledger, .pomodoro, .analytics, .liveActivities]) {
            try StopSegmentUseCase(repository: requiredTimeRepository()).execute(segmentID: segment.id)
            try cancelPomodoroIfNeeded(sessionID: segment.sessionID)
        }
    }

    func pause(segment: TimeSegment) {
        perform(refresh: [.ledger, .pomodoro, .analytics, .liveActivities]) {
            try PauseSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: segment.sessionID)
            try interruptPomodoroIfNeeded(sessionID: segment.sessionID)
        }
    }

    func resume(session: TimeSession) {
        perform(refresh: [.ledger, .pomodoro, .analytics, .liveActivities]) {
            _ = try ResumeSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: session.id)
            try resumePomodoroIfNeeded(sessionID: session.id)
        }
    }

    func stop(session: TimeSession) {
        perform(refresh: [.ledger, .pomodoro, .analytics, .liveActivities]) {
            try StopSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: session.id)
            try cancelPomodoroIfNeeded(sessionID: session.id)
        }
    }

    func presentNewTask(parentID: UUID? = nil) {
        taskEditorDraft = TaskEditorDraft(parentID: parentID)
    }

    func presentEditTask(_ task: TaskNode) {
        taskEditorDraft = TaskEditorDraft(task: task, checklistItems: checklistItems(for: task.id))
    }

    @discardableResult
    func saveTaskDraft(_ draft: TaskEditorDraft) -> Bool {
        let sanitizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            errorMessage = AppStrings.localized("task.nameRequired")
            return false
        }

        let didSave = perform(refresh: [.tasks, .checklist, .analytics, .liveActivities]) {
            if let taskID = draft.taskID {
                try UpdateTaskUseCase(repository: requiredTaskRepository()).execute(
                    taskID: taskID,
                    title: sanitizedTitle,
                    status: draft.status,
                    parentID: draft.parentID,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName,
                    notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    estimatedSeconds: draft.estimatedMinutes.map { $0 * 60 },
                    dueAt: draft.hasDueDate ? draft.dueAt : nil
                )
                try saveChecklistDrafts(draft.checklistItems, taskID: taskID)
                selectedTaskID = taskID
            } else {
                let task = try CreateTaskUseCase(repository: requiredTaskRepository()).execute(
                    title: sanitizedTitle,
                    parentID: draft.parentID,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName
                )
                try UpdateTaskUseCase(repository: requiredTaskRepository()).execute(
                    taskID: task.id,
                    title: sanitizedTitle,
                    status: draft.status,
                    parentID: draft.parentID,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName,
                    notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    estimatedSeconds: draft.estimatedMinutes.map { $0 * 60 },
                    dueAt: draft.hasDueDate ? draft.dueAt : nil
                )
                try saveChecklistDrafts(draft.checklistItems, taskID: task.id)
                selectedTaskID = task.id
            }
        }
        if didSave {
            taskEditorDraft = nil
        }
        return didSave
    }

    func setPreferredColorScheme(_ value: String) {
        setPreference(.preferredColorScheme, valueJSON: PreferenceJSON.encode(value))
    }

    func setPomodoroDefaultMode(_ value: String) {
        setPreference(.pomodoroDefaultMode, valueJSON: PreferenceJSON.encode(value))
    }

    func setDefaultFocusMinutes(_ value: Int) {
        setPreference(.defaultFocusMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...480)))
    }

    func setDefaultBreakMinutes(_ value: Int) {
        setPreference(.defaultBreakMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...480)))
    }

    func setDefaultPomodoroRounds(_ value: Int) {
        setPreference(.defaultPomodoroRounds, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...24)))
    }

    func setAllowParallelTimers(_ value: Bool) {
        setPreference(.allowParallelTimers, valueJSON: PreferenceJSON.encode(value))
    }

    func setShowGrossAndWallTogether(_ value: Bool) {
        setPreference(.showGrossAndWallTogether, valueJSON: PreferenceJSON.encode(value))
    }

    func setCloudSyncEnabled(_ value: Bool) {
        setPreference(.cloudSyncEnabled, valueJSON: PreferenceJSON.encode(value))
        UserDefaults.standard.set(value, forKey: AppCloudSync.enabledKey)
    }

    func setQuickStartTaskIDs(_ ids: [UUID]) {
        setPreference(.quickStartTaskIDs, valueJSON: PreferenceJSON.encode(ids.map(\.uuidString)))
    }

    func archiveSelectedTask(taskID: UUID? = nil) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        perform(refresh: [.tasks, .analytics, .liveActivities]) {
            try ArchiveTaskUseCase(repository: requiredTaskRepository()).execute(taskID: targetID)
            if self.selectedTaskID == targetID {
                self.selectedTaskID = tasks.first(where: { $0.id != targetID })?.id
            }
        }
    }

    func setTaskStatus(_ status: TaskStatus, taskID: UUID? = nil) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        perform(refresh: [.tasks, .analytics, .liveActivities]) {
            try SetTaskStatusUseCase(repository: requiredTaskRepository()).execute(taskID: targetID, status: status)
        }
    }

    func deleteSelectedTask(taskID: UUID? = nil) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        perform(refresh: [.tasks, .analytics, .liveActivities]) {
            try SoftDeleteTaskUseCase(repository: requiredTaskRepository()).execute(taskID: targetID)
            if self.selectedTaskID == targetID {
                self.selectedTaskID = tasks.first(where: { $0.id != targetID })?.id
            }
        }
    }

    func presentManualTime(taskID: UUID? = nil) {
        let target = taskID ?? selectedTaskID ?? tasks.first?.id
        manualTimeDraft = ManualTimeDraft(taskID: target, tasks: tasks)
    }

    func saveManualTimeDraft(_ draft: ManualTimeDraft) {
        guard let taskID = draft.taskID else {
            errorMessage = AppStrings.localized("task.selectRequired")
            return
        }
        guard draft.endedAt > draft.startedAt else {
            errorMessage = AppStrings.localized("time.endAfterStart")
            return
        }

        perform(refresh: [.ledger, .analytics, .liveActivities]) {
            _ = try AddManualTimeUseCase(repository: requiredTimeRepository()).execute(
                taskID: taskID,
                startedAt: draft.startedAt,
                endedAt: draft.endedAt,
                note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Manual"
            )
        }
        manualTimeDraft = nil
    }

    func presentEditSegment(_ segment: TimeSegment) {
        segmentEditorDraft = SegmentEditorDraft(segment: segment, note: note(for: segment))
    }

    func saveSegmentDraft(_ draft: SegmentEditorDraft) {
        guard let taskID = draft.taskID else {
            errorMessage = AppStrings.localized("task.selectRequired")
            return
        }

        let endedAt = draft.isActive ? nil : draft.endedAt
        if let endedAt, endedAt <= draft.startedAt {
            errorMessage = AppStrings.localized("time.endAfterStart")
            return
        }

        perform(refresh: [.ledger, .analytics, .liveActivities]) {
            try UpdateSegmentUseCase(repository: requiredTimeRepository()).execute(
                segmentID: draft.segmentID,
                taskID: taskID,
                startedAt: draft.startedAt,
                endedAt: endedAt,
                note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
            selectedTaskID = taskID
        }
        segmentEditorDraft = nil
    }

    func deleteSegment(_ segmentID: UUID) {
        perform(refresh: [.ledger, .analytics, .liveActivities]) {
            try SoftDeleteSegmentUseCase(repository: requiredTimeRepository()).execute(segmentID: segmentID)
        }
        segmentEditorDraft = nil
    }

    func replaceWithDemoData() {
        perform {
            guard let modelContext else { throw StoreError.notConfigured }
            try SeedData.replaceWithDemoData(context: modelContext)
        }
    }

    func clearAllData() {
        perform {
            guard let modelContext else { throw StoreError.notConfigured }
            try SeedData.clearAll(context: modelContext)
            selectedTaskID = nil
        }
    }

    func clearDemoData() {
        perform {
            guard let modelContext else { throw StoreError.notConfigured }
            try SeedData.clearDemoData(context: modelContext)
            if let selectedTaskID, tasks.contains(where: { $0.id == selectedTaskID && $0.deviceID == "demo" }) {
                self.selectedTaskID = nil
            }
        }
    }

    @discardableResult
    func optimizeDatabase() -> Int {
        var removedCount = 0
        perform {
            guard let modelContext else { throw StoreError.notConfigured }
            let allTasks = try modelContext.fetch(FetchDescriptor<TaskNode>())
            let validTaskIDs = Set(allTasks.filter { $0.deletedAt == nil }.map(\.id))
            let allSegments = try modelContext.fetch(FetchDescriptor<TimeSegment>())
            let allSessions = try modelContext.fetch(FetchDescriptor<TimeSession>())
            let allRuns = try modelContext.fetch(FetchDescriptor<PomodoroRun>())

            let orphanSegments = allSegments.filter { !validTaskIDs.contains($0.taskID) }
            let orphanSessions = allSessions.filter { !validTaskIDs.contains($0.taskID) }
            let orphanRuns = allRuns.filter { !validTaskIDs.contains($0.taskID) }
            let orphanSegmentIDs = Set(orphanSegments.map(\.id))
            let sessionIDsWithSegments = Set(allSegments.filter { !orphanSegmentIDs.contains($0.id) }.map(\.sessionID))
            let emptySessions = allSessions.filter { !sessionIDsWithSegments.contains($0.id) }
            var removedSessionIDs = Set<UUID>()
            let removableSessions = (orphanSessions + emptySessions).filter { removedSessionIDs.insert($0.id).inserted }

            for segment in orphanSegments {
                modelContext.delete(segment)
            }
            for session in removableSessions {
                modelContext.delete(session)
            }
            for run in orphanRuns {
                modelContext.delete(run)
            }

            removedCount = orphanSegments.count + removableSessions.count + orphanRuns.count
            try modelContext.save()
        }
        return removedCount
    }

    func csvExport() -> String {
        let formatter = ISO8601DateFormatter()
        let header = ["Task", "Path", "Start", "End", "Duration Seconds", "Source", "Note"]
        let rows = allSegments
            .filter { $0.deletedAt == nil }
            .sorted { $0.startedAt < $1.startedAt }
            .map { segment in
                [
                    displayTitle(for: segment),
                    displayPath(for: segment),
                    formatter.string(from: segment.startedAt),
                    segment.endedAt.map { formatter.string(from: $0) } ?? "",
                    "\(Int((segment.endedAt ?? Date()).timeIntervalSince(segment.startedAt)))",
                    segment.source.rawValue,
                    note(for: segment)
                ]
            }
        return ([header] + rows)
            .map { $0.map(Self.csvEscaped).joined(separator: ",") }
            .joined(separator: "\n")
    }

    func startPomodoroForSelectedTask(focusSeconds: Int = 25 * 60, breakSeconds: Int = 5 * 60, targetRounds: Int = 1) {
        guard let selectedTaskID else {
            errorMessage = AppStrings.localized("task.selectBeforePomodoro")
            return
        }
        perform(refresh: [.ledger, .pomodoro, .analytics, .liveActivities]) {
            if !preferences.allowParallelTimers {
                try pauseOtherActiveSegments(excluding: selectedTaskID)
            }
            _ = try StartPomodoroUseCase(repository: requiredPomodoroRepository()).execute(
                taskID: selectedTaskID,
                focusSeconds: focusSeconds,
                breakSeconds: breakSeconds,
                targetRounds: targetRounds
            )
        }
    }

    func completeActivePomodoro() {
        guard let run = activePomodoroRun else { return }
        perform(refresh: [.ledger, .pomodoro, .analytics, .liveActivities]) {
            try CompletePomodoroFocusUseCase(repository: requiredPomodoroRepository()).execute(runID: run.id)
        }
    }

    func cancelActivePomodoro() {
        guard let run = activePomodoroRun else { return }
        perform(refresh: [.ledger, .pomodoro, .analytics, .liveActivities]) {
            try CancelPomodoroUseCase(repository: requiredPomodoroRepository()).execute(runID: run.id)
        }
    }

    var selectedTask: TaskNode? {
        guard let selectedTaskID else { return nil }
        return task(for: selectedTaskID)
    }

    var activePomodoroRun: PomodoroRun? {
        pomodoroRuns.first { run in
            run.deletedAt == nil &&
            run.endedAt == nil &&
            [.planned, .focusing, .shortBreak, .longBreak, .interrupted].contains(run.state)
        }
    }

    var recentTasks: [TaskNode] {
        tasks.filter { $0.status == .active }.prefix(4).map { $0 }
    }

    func frequentRecentTasks(excluding excludedIDs: Set<UUID> = [], limit: Int = 3) -> [TaskNode] {
        guard limit > 0 else { return [] }

        let availableTasks = tasks.filter {
            $0.deletedAt == nil &&
            $0.status != .archived &&
            !excludedIDs.contains($0.id)
        }
        let availableIDs = Set(availableTasks.map(\.id))
        let segmentsByTaskID = Dictionary(grouping: allSegments.filter {
            $0.deletedAt == nil && availableIDs.contains($0.taskID)
        }, by: \.taskID)

        let rankedTasks = availableTasks.compactMap { task -> (task: TaskNode, count: Int, lastStartedAt: Date)? in
            guard let segments = segmentsByTaskID[task.id], !segments.isEmpty else { return nil }
            let lastStartedAt = segments.map(\.startedAt).max() ?? task.updatedAt
            return (task, segments.count, lastStartedAt)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.lastStartedAt > rhs.lastStartedAt
        }
        .map(\.task)

        let rankedIDs = Set(rankedTasks.map(\.id))
        let fallbackTasks = recentTasks.filter {
            !excludedIDs.contains($0.id) && !rankedIDs.contains($0.id)
        }

        return Array((rankedTasks + fallbackTasks).prefix(limit))
    }

    var archivedTasks: [TaskNode] {
        tasks.filter { $0.status == .archived }
    }

    var syncStatus: SyncStatus {
        SyncStatus(
            mode: AppCloudSync.persistenceMode,
            containerIdentifier: AppCloudSync.containerIdentifier,
            deviceID: DeviceIdentity.current,
            lastError: AppCloudSync.lastError,
            accountStatus: cloudAccountStatus
        )
    }

    var pausedSessions: [TimeSession] {
        let activeSessionIDs = Set(activeSegments.map(\.sessionID))
        return sessions.filter { session in
            session.endedAt == nil &&
            session.deletedAt == nil &&
            !activeSessionIDs.contains(session.id)
        }
    }

    var timelineSegments: [TimeSegment] {
        sortedTodaySegments
    }

    var todayGrossSeconds: Int {
        todayGrossSeconds(now: Date())
    }

    var todayWallSeconds: Int {
        todayWallSeconds(now: Date())
    }

    func todayGrossSeconds(now: Date) -> Int {
        aggregationService.totalSeconds(segments: todaySegments, mode: .gross, now: now)
    }

    func todayWallSeconds(now: Date) -> Int {
        aggregationService.totalSeconds(segments: todaySegments, mode: .wallClock, now: now)
    }

    func daySeconds(for date: Date, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else { return 0 }
        let segments = allSegments.filter { overlaps($0, interval: interval, now: now) }
        return clippedSeconds(segments: segments, interval: interval, mode: mode, now: now)
    }

    func overlapSeconds(now: Date) -> Int {
        max(0, todayGrossSeconds(now: now) - todayWallSeconds(now: now))
    }

    var overlapSeconds: Int {
        max(0, todayGrossSeconds - todayWallSeconds)
    }

    var completedPomodoroCount: Int {
        let today = Calendar.current.dateInterval(of: .day, for: Date())
        return pomodoroRuns.filter { run in
            run.state == .completed &&
            run.deletedAt == nil &&
            today?.contains(run.endedAt ?? run.updatedAt) == true
        }.count
    }

    var averageFocusSeconds: Int {
        let focus = todaySegments.filter { $0.source == .pomodoro }
        guard !focus.isEmpty else { return 0 }
        return aggregationService.grossSeconds(focus) / focus.count
    }

    func task(for id: UUID) -> TaskNode? {
        taskByID[id]
    }

    func activeSegment(for taskID: UUID) -> TimeSegment? {
        activeSegments.first { $0.taskID == taskID }
    }

    func pausedSession(for taskID: UUID) -> TimeSession? {
        pausedSessions.first { $0.taskID == taskID }
    }

    func activePomodoroRun(for taskID: UUID) -> PomodoroRun? {
        pomodoroRuns.first { run in
            run.taskID == taskID &&
            run.deletedAt == nil &&
            run.endedAt == nil &&
            [.planned, .focusing, .shortBreak, .longBreak, .interrupted].contains(run.state)
        }
    }

    func taskTitle(for run: PomodoroRun) -> String {
        task(for: run.taskID)?.title ?? AppStrings.localized("task.deleted")
    }

    func pomodoroRemainingSeconds(for run: PomodoroRun, now: Date = Date()) -> Int {
        guard [.focusing, .interrupted].contains(run.state) else {
            return run.focusSecondsPlanned
        }
        return max(0, run.focusSecondsPlanned - pomodoroElapsedFocusSeconds(for: run, now: now))
    }

    func pomodoroProgress(for run: PomodoroRun, now: Date = Date()) -> Double {
        guard run.focusSecondsPlanned > 0 else { return 0 }
        let remaining = pomodoroRemainingSeconds(for: run, now: now)
        return min(1, max(0, 1 - Double(remaining) / Double(run.focusSecondsPlanned)))
    }

    func pomodoroStateLabel(for run: PomodoroRun) -> String {
        switch run.state {
        case .planned:
            return AppStrings.localized("pomodoro.state.ready")
        case .focusing:
            return AppStrings.localized("pomodoro.state.focus")
        case .shortBreak:
            return AppStrings.localized("pomodoro.state.shortBreak")
        case .longBreak:
            return AppStrings.localized("pomodoro.state.longBreak")
        case .completed:
            return AppStrings.localized("pomodoro.state.completed")
        case .cancelled:
            return AppStrings.localized("pomodoro.state.cancelled")
        case .interrupted:
            return AppStrings.localized("pomodoro.state.interrupted")
        }
    }

    func pomodoroElapsedFocusSeconds(for run: PomodoroRun, now: Date = Date()) -> Int {
        guard let sessionID = run.sessionID else { return 0 }
        let segments = allSegments.filter { segment in
            segment.sessionID == sessionID &&
            segment.source == .pomodoro &&
            segment.deletedAt == nil
        }
        return aggregationService.grossSeconds(segments, now: now)
    }

    func path(for task: TaskNode) -> String {
        taskPathByID[task.id] ?? task.title
    }

    func displayTitle(for segment: TimeSegment) -> String {
        task(for: segment.taskID)?.title ?? AppStrings.localized("task.deleted")
    }

    func displayPath(for segment: TimeSegment) -> String {
        guard taskByID[segment.taskID] != nil else { return AppStrings.localized("task.deleted.path") }
        return taskParentPathByID[segment.taskID] ?? ""
    }

    func note(for segment: TimeSegment) -> String {
        sessions.first { $0.id == segment.sessionID }?.note ?? ""
    }

    func secondsForTaskTotal(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        ledgerSummaryService.totalSeconds(taskIDs: [task.id], segments: allSegments, mode: mode, now: now)
    }

    func secondsForTaskTotalRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        let ids = taskAndDescendantIDs(for: task.id)
        return ledgerSummaryService.totalSeconds(taskIDs: ids, segments: allSegments, mode: mode, now: now)
    }

    func secondsForTaskToday(_ task: TaskNode, mode: AggregationMode = .gross) -> Int {
        let now = Date()
        guard let interval = Calendar.current.dateInterval(of: .day, for: now) else { return 0 }
        return ledgerSummaryService.secondsInInterval(taskIDs: [task.id], segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskTodayRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .day, for: now) else { return 0 }
        let ids = taskAndDescendantIDs(for: task.id)
        return ledgerSummaryService.secondsInInterval(taskIDs: ids, segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskThisWeek(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return ledgerSummaryService.secondsInInterval(taskIDs: [task.id], segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func secondsForTaskThisWeekRollup(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let ids = taskAndDescendantIDs(for: task.id)
        return ledgerSummaryService.secondsInInterval(taskIDs: ids, segments: allSegments, interval: interval, mode: mode, now: now)
    }

    func toggleChecklistItem(_ item: ChecklistItem) {
        perform(refresh: [.checklist, .analytics]) {
            item.isCompleted.toggle()
            item.completedAt = item.isCompleted ? Date() : nil
            item.updatedAt = Date()
            item.clientMutationID = UUID()
            try modelContext?.save()
        }
    }

    func recentSegments(for task: TaskNode, limit: Int = 6) -> [TimeSegment] {
        allSegments
            .filter { $0.taskID == task.id && $0.deletedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit)
            .map { $0 }
    }

    func analyticsSnapshot(for range: AnalyticsRange, now: Date = Date()) -> AnalyticsSnapshot {
        analyticsDomainStore.snapshot(
            range: range,
            tasks: tasks,
            segments: allSegments,
            sessions: sessions,
            taskPathByID: taskPathByID,
            taskParentPathByID: taskParentPathByID,
            now: now
        )
    }

    func analyticsOverview(for range: AnalyticsRange, now: Date = Date()) -> AnalyticsOverview {
        analyticsSnapshot(for: range, now: now).overview
    }

    func dailyBreakdown(range: AnalyticsRange, now: Date = Date()) -> [DailyAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).daily
    }

    func hourlyBreakdown(for date: Date = Date(), now: Date = Date()) -> [HourlyAnalyticsPoint] {
        analyticsEngine.hourlyBreakdown(segments: allSegments, date: date, now: now)
    }

    func taskBreakdown(range: AnalyticsRange, now: Date = Date()) -> [TaskAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).taskBreakdown
    }

    func overlapSegments(range: AnalyticsRange, now: Date = Date()) -> [OverlapAnalyticsPoint] {
        analyticsSnapshot(for: range, now: now).overlaps
    }

    func rootTasks() -> [TaskNode] {
        childrenByParentID[nil] ?? []
    }

    func children(of task: TaskNode) -> [TaskNode] {
        childrenByParentID[task.id] ?? []
    }

    func ancestorTaskIDs(for taskID: UUID) -> [UUID] {
        var result: [UUID] = []
        var cursor = taskByID[taskID]
        var visited: Set<UUID> = []
        while let parentID = cursor?.parentID, !visited.contains(parentID) {
            result.append(parentID)
            visited.insert(parentID)
            cursor = taskByID[parentID]
        }
        return result
    }

    func validParentTasks(for taskID: UUID?) -> [TaskNode] {
        taskTreeService.validParentTasks(for: taskID, tasks: tasks)
    }

    func taskTreeRows(expandedTaskIDs: Set<UUID>) -> [TaskTreeRowModel] {
        TaskTreeFlattener.visibleRows(
            rootTasks: rootTasks(),
            children: { [weak self] task in
                self?.children(of: task) ?? []
            },
            expandedTaskIDs: expandedTaskIDs
        )
    }

    func checklistItems(for taskID: UUID) -> [ChecklistItem] {
        checklistByTaskID[taskID] ?? []
    }

    func checklistProgress(for taskID: UUID) -> ChecklistProgress {
        rollupService.checklistProgress(for: taskID, checklistItems: checklistItems)
    }

    func rollup(for taskID: UUID) -> TaskRollup? {
        taskRollups[taskID]
    }

    private func rebuildTaskIndexes() {
        let indexes = taskTreeService.indexes(tasks: tasks)
        taskByID = indexes.taskByID
        childrenByParentID = indexes.childrenByParentID
        taskPathByID = indexes.taskPathByID
        taskParentPathByID = indexes.taskParentPathByID
    }

    private func rebuildChecklistIndexes() {
        checklistByTaskID = Dictionary(grouping: checklistItems.filter { $0.deletedAt == nil }, by: \.taskID)
            .mapValues { items in
                items.sorted { lhs, rhs in
                    if lhs.sortOrder == rhs.sortOrder {
                        return lhs.createdAt < rhs.createdAt
                    }
                    return lhs.sortOrder < rhs.sortOrder
                }
            }
    }

    private func segmentsForAnalytics(range: AnalyticsRange, now: Date) -> [TimeSegment] {
        guard let interval = analyticsInterval(for: range, now: now) else { return allSegments }
        return allSegments.filter { overlaps($0, interval: interval, now: now) }
    }

    private func analyticsInterval(for range: AnalyticsRange, now: Date) -> DateInterval? {
        let calendar = Calendar.current
        switch range {
        case .today:
            return calendar.dateInterval(of: .day, for: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now)
        }
    }

    private func overlaps(_ segment: TimeSegment, interval: DateInterval, now: Date) -> Bool {
        let end = segment.endedAt ?? now
        return segment.startedAt < interval.end && end > interval.start
    }

    private func clippedSeconds(segments: [TimeSegment], interval: DateInterval, mode: AggregationMode, now: Date) -> Int {
        let intervals = segments.compactMap { clippedInterval(for: $0, in: interval, now: now) }
        switch mode {
        case .gross:
            return intervals.reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start)) }
        case .wallClock:
            return aggregationService.mergeOverlappingIntervals(intervals).reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start)) }
        }
    }

    private func clippedInterval(for segment: TimeSegment, in interval: DateInterval, now: Date) -> DateInterval? {
        guard segment.deletedAt == nil else { return nil }
        let end = segment.endedAt ?? now
        let start = max(segment.startedAt, interval.start)
        let clippedEnd = min(end, interval.end)
        guard clippedEnd > start else { return nil }
        return DateInterval(start: start, end: clippedEnd)
    }

    private func taskAndDescendantIDs(for taskID: UUID, visited: Set<UUID> = []) -> Set<UUID> {
        taskTreeService.taskAndDescendantIDs(for: taskID, childrenByParentID: childrenByParentID, visited: visited)
    }

    @discardableResult
    private func perform(refresh scopes: Set<RefreshScope>? = nil, _ action: () throws -> Void) -> Bool {
        do {
            try action()
            try refresh(scopes: scopes ?? Self.fullRefreshScopes)
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
            self?.refreshQuietly()
        }
    }

    private func interruptPomodoroIfNeeded(sessionID: UUID) throws {
        guard let run = pomodoroRuns.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }),
              run.state == .focusing else {
            return
        }
        run.state = .interrupted
        run.updatedAt = Date()
        run.clientMutationID = UUID()
        try modelContext?.save()
    }

    private func resumePomodoroIfNeeded(sessionID: UUID) throws {
        guard let run = pomodoroRuns.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }),
              run.state == .interrupted else {
            return
        }
        run.state = .focusing
        run.updatedAt = Date()
        run.clientMutationID = UUID()
        try modelContext?.save()
    }

    private func cancelPomodoroIfNeeded(sessionID: UUID) throws {
        guard let run = pomodoroRuns.first(where: { $0.sessionID == sessionID && $0.deletedAt == nil && $0.endedAt == nil }) else {
            return
        }
        run.state = .cancelled
        run.endedAt = Date()
        run.updatedAt = Date()
        run.clientMutationID = UUID()
        try modelContext?.save()
    }

    private func setPreference(_ key: AppPreferenceKey, valueJSON: String) {
        perform(refresh: [.preferences]) {
            guard let modelContext else { throw StoreError.notConfigured }
            let rawKey = key.rawValue
            let descriptor = FetchDescriptor<SyncedPreference>(
                predicate: #Predicate { $0.key == rawKey && $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            let existing = try modelContext.fetch(descriptor)
            let target = existing.first ?? SyncedPreference(
                key: key.rawValue,
                valueJSON: valueJSON,
                deviceID: DeviceIdentity.current
            )
            if existing.isEmpty {
                modelContext.insert(target)
            }
            target.valueJSON = valueJSON
            target.updatedAt = Date()
            target.deviceID = DeviceIdentity.current
            target.clientMutationID = UUID()
            for duplicate in existing.dropFirst() {
                duplicate.deletedAt = Date()
                duplicate.updatedAt = Date()
                duplicate.clientMutationID = UUID()
            }
            try modelContext.save()
        }
    }

    private func saveChecklistDrafts(_ drafts: [ChecklistEditorDraft], taskID: UUID) throws {
        guard let modelContext else { throw StoreError.notConfigured }
        try checklistDraftService.save(drafts: drafts, taskID: taskID, context: modelContext)
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

    private func requiredTaskRepository() throws -> TaskRepository {
        guard let taskRepository else { throw StoreError.notConfigured }
        return taskRepository
    }

    private func requiredTimeRepository() throws -> TimeTrackingRepository {
        guard let timeRepository else { throw StoreError.notConfigured }
        return timeRepository
    }

    private func requiredPomodoroRepository() throws -> PomodoroRepository {
        guard let pomodoroRepository else { throw StoreError.notConfigured }
        return pomodoroRepository
    }

    enum StoreError: LocalizedError {
        case notConfigured

        var errorDescription: String? {
            "TimeTrackerStore has not been configured with a ModelContext."
        }
    }

    private static func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
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

struct TaskEditorDraft: Identifiable {
    let id = UUID()
    var taskID: UUID?
    var title: String
    var status: TaskStatus
    var parentID: UUID?
    var colorHex: String
    var iconName: String
    var notes: String
    var estimatedMinutes: Int?
    var hasDueDate: Bool
    var dueAt: Date
    var checklistItems: [ChecklistEditorDraft]

    init(parentID: UUID?) {
        self.taskID = nil
        self.title = ""
        self.status = .active
        self.parentID = parentID
        self.colorHex = "1677FF"
        self.iconName = "checkmark.circle"
        self.notes = ""
        self.estimatedMinutes = nil
        self.hasDueDate = false
        self.dueAt = Date()
        self.checklistItems = []
    }

    init(task: TaskNode, checklistItems: [ChecklistItem]) {
        self.taskID = task.id
        self.title = task.title
        self.status = task.status
        self.parentID = task.parentID
        self.colorHex = task.colorHex ?? "1677FF"
        self.iconName = task.iconName ?? "checkmark.circle"
        self.notes = task.notes ?? ""
        self.estimatedMinutes = task.estimatedSeconds.map { $0 / 60 }
        self.hasDueDate = task.dueAt != nil
        self.dueAt = task.dueAt ?? Date()
        self.checklistItems = checklistItems.map(ChecklistEditorDraft.init(item:))
    }
}

struct ChecklistEditorDraft: Identifiable, Equatable {
    let id: UUID
    var existingID: UUID?
    var title: String
    var isCompleted: Bool

    nonisolated init(title: String = "", isCompleted: Bool = false) {
        self.id = UUID()
        self.existingID = nil
        self.title = title
        self.isCompleted = isCompleted
    }

    nonisolated init(item: ChecklistItem) {
        self.id = item.id
        self.existingID = item.id
        self.title = item.title
        self.isCompleted = item.isCompleted
    }
}

struct ManualTimeDraft: Identifiable {
    let id = UUID()
    var taskID: UUID?
    var startedAt: Date
    var endedAt: Date
    var note: String

    init(taskID: UUID?, tasks: [TaskNode]) {
        let end = Date()
        self.taskID = taskID ?? tasks.first?.id
        self.startedAt = end.addingTimeInterval(-30 * 60)
        self.endedAt = end
        self.note = ""
    }
}

struct SegmentEditorDraft: Identifiable {
    let id = UUID()
    let segmentID: UUID
    var taskID: UUID?
    var startedAt: Date
    var endedAt: Date
    var isActive: Bool
    var note: String
    var source: TimeSessionSource

    init(segment: TimeSegment, note: String) {
        self.segmentID = segment.id
        self.taskID = segment.taskID
        self.startedAt = segment.startedAt
        self.endedAt = segment.endedAt ?? Date()
        self.isActive = segment.endedAt == nil
        self.note = note
        self.source = segment.source
    }
}

struct SyncStatus {
    let mode: String
    let containerIdentifier: String
    let deviceID: String
    let lastError: String?
    let accountStatus: String

    var isCloudBacked: Bool {
        mode == "iCloud"
    }

    var storageStatusText: String {
        isCloudBacked ? "SwiftData + iCloud" : mode
    }
}

enum AnalyticsRange: String, CaseIterable, Identifiable {
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

struct AnalyticsOverview {
    let grossSeconds: Int
    let wallSeconds: Int
    let overlapSeconds: Int
    let pomodoroCount: Int
    let averageFocusSeconds: Int
}

struct DailyAnalyticsPoint: Identifiable {
    let date: Date
    let grossSeconds: Int
    let wallSeconds: Int
    let label: String

    var id: Date { date }
}

struct HourlyAnalyticsPoint: Identifiable {
    let hour: Int
    let grossSeconds: Int
    let wallSeconds: Int

    var id: Int { hour }
    var label: String {
        hour == 0 ? "00" : "\(hour)"
    }
}

struct TaskAnalyticsPoint: Identifiable {
    let taskID: UUID
    let title: String
    let path: String
    let colorHex: String?
    let iconName: String?
    let status: TaskStatus?
    let grossSeconds: Int
    let wallSeconds: Int

    var id: UUID { taskID }
}

struct OverlapAnalyticsPoint: Identifiable {
    let start: Date
    let end: Date
    let firstTitle: String
    let secondTitle: String

    var id: String {
        "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))-\(firstTitle)-\(secondTitle)"
    }

    var durationSeconds: Int {
        max(0, Int(end.timeIntervalSince(start)))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
