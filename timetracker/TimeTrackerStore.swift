import Combine
import CoreData
import Foundation
import SwiftData

@MainActor
final class TimeTrackerStore: ObservableObject {
    @Published private(set) var tasks: [TaskNode] = []
    @Published private(set) var activeSegments: [TimeSegment] = []
    @Published private(set) var todaySegments: [TimeSegment] = []
    @Published private(set) var allSegments: [TimeSegment] = []
    @Published private(set) var sessions: [TimeSession] = []
    @Published private(set) var pomodoroRuns: [PomodoroRun] = []
    @Published private(set) var countdownEvents: [CountdownEvent] = []
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
    private var syncObservers: [NSObjectProtocol] = []

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
        let storage = syncStatus.isCloudBacked ? "iCloud 存储" : "本地存储"
        return "\(storage)：\(syncStatus.accountStatus)。已刷新本机视图；若另一台设备刚写入，系统完成导入后这里会自动更新。"
    }

    func refreshCloudAccountStatus() async {
        await AppCloudSync.refreshAccountStatus()
        cloudAccountStatus = AppCloudSync.accountStatus
    }

    func addCountdownEvent() {
        perform {
            guard let modelContext else { throw StoreError.notConfigured }
            let event = CountdownEvent(
                title: "新事件",
                date: Date().addingTimeInterval(30 * 24 * 60 * 60),
                deviceID: DeviceIdentity.current
            )
            modelContext.insert(event)
            try modelContext.save()
        }
    }

    func updateCountdownEvent(_ event: CountdownEvent, title: String? = nil, date: Date? = nil) {
        perform {
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
        perform {
            event.deletedAt = Date()
            event.updatedAt = Date()
            event.clientMutationID = UUID()
            try modelContext?.save()
        }
    }

    func refresh() throws {
        guard let taskRepository, let timeRepository else { return }
        tasks = try taskRepository.allNodes()
        activeSegments = try timeRepository.activeSegments()
        allSegments = try timeRepository.allSegments()
        sessions = try timeRepository.sessions()
        pomodoroRuns = try pomodoroRepository?.runs() ?? []
        countdownEvents = try fetchCountdownEvents()

        let range = Calendar.current.dateInterval(of: .day, for: Date()) ?? DateInterval(start: Date(), duration: 24 * 60 * 60)
        todaySegments = try timeRepository.segments(from: range.start, to: range.end)

        if selectedTaskID == nil {
            selectedTaskID = activeSegments.first?.taskID ?? tasks.first?.id
        }
        syncLiveActivitiesIfAvailable()
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
        perform {
            if activeSegment(for: taskID) != nil {
                return
            }
            if let pausedSession = pausedSession(for: taskID) {
                _ = try ResumeSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: pausedSession.id)
                try resumePomodoroIfNeeded(sessionID: pausedSession.id)
                return
            }
            _ = try StartTaskUseCase(repository: requiredTimeRepository()).execute(taskID: taskID, source: .timer)
        }
    }

    func stop(segment: TimeSegment) {
        perform {
            try StopSegmentUseCase(repository: requiredTimeRepository()).execute(segmentID: segment.id)
            try cancelPomodoroIfNeeded(sessionID: segment.sessionID)
        }
    }

    func pause(segment: TimeSegment) {
        perform {
            try PauseSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: segment.sessionID)
            try interruptPomodoroIfNeeded(sessionID: segment.sessionID)
        }
    }

    func resume(session: TimeSession) {
        perform {
            _ = try ResumeSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: session.id)
            try resumePomodoroIfNeeded(sessionID: session.id)
        }
    }

    func stop(session: TimeSession) {
        perform {
            try StopSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: session.id)
            try cancelPomodoroIfNeeded(sessionID: session.id)
        }
    }

    func presentNewTask(parentID: UUID? = nil) {
        taskEditorDraft = TaskEditorDraft(parentID: parentID)
    }

    func presentEditTask(_ task: TaskNode) {
        taskEditorDraft = TaskEditorDraft(task: task)
    }

    func saveTaskDraft(_ draft: TaskEditorDraft) {
        let sanitizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            errorMessage = "任务名称不能为空。"
            return
        }

        perform {
            if let taskID = draft.taskID {
                try UpdateTaskUseCase(repository: requiredTaskRepository()).execute(
                    taskID: taskID,
                    title: sanitizedTitle,
                    kind: draft.kind,
                    status: draft.status,
                    parentID: draft.parentID,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName,
                    notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    estimatedSeconds: draft.estimatedMinutes.map { $0 * 60 },
                    dueAt: draft.hasDueDate ? draft.dueAt : nil
                )
                selectedTaskID = taskID
            } else {
                let task = try CreateTaskUseCase(repository: requiredTaskRepository()).execute(
                    title: sanitizedTitle,
                    kind: draft.kind,
                    parentID: draft.parentID,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName
                )
                try UpdateTaskUseCase(repository: requiredTaskRepository()).execute(
                    taskID: task.id,
                    title: sanitizedTitle,
                    kind: draft.kind,
                    status: draft.status,
                    parentID: draft.parentID,
                    colorHex: draft.colorHex,
                    iconName: draft.iconName,
                    notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    estimatedSeconds: draft.estimatedMinutes.map { $0 * 60 },
                    dueAt: draft.hasDueDate ? draft.dueAt : nil
                )
                selectedTaskID = task.id
            }
        }
        taskEditorDraft = nil
    }

    func archiveSelectedTask(taskID: UUID? = nil) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        perform {
            try ArchiveTaskUseCase(repository: requiredTaskRepository()).execute(taskID: targetID)
            if self.selectedTaskID == targetID {
                self.selectedTaskID = tasks.first(where: { $0.id != targetID })?.id
            }
        }
    }

    func setTaskStatus(_ status: TaskStatus, taskID: UUID? = nil) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        perform {
            try SetTaskStatusUseCase(repository: requiredTaskRepository()).execute(taskID: targetID, status: status)
        }
    }

    func deleteSelectedTask(taskID: UUID? = nil) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        perform {
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
            errorMessage = "请选择任务。"
            return
        }
        guard draft.endedAt > draft.startedAt else {
            errorMessage = "结束时间必须晚于开始时间。"
            return
        }

        perform {
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
            errorMessage = "请选择任务。"
            return
        }

        let endedAt = draft.isActive ? nil : draft.endedAt
        if let endedAt, endedAt <= draft.startedAt {
            errorMessage = "结束时间必须晚于开始时间。"
            return
        }

        perform {
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
        perform {
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
            errorMessage = "请选择一个任务再开始番茄钟。"
            return
        }
        perform {
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
        perform {
            try CompletePomodoroFocusUseCase(repository: requiredPomodoroRepository()).execute(runID: run.id)
        }
    }

    func cancelActivePomodoro() {
        guard let run = activePomodoroRun else { return }
        perform {
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
        todaySegments.sorted { $0.startedAt > $1.startedAt }
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
        tasks.first { $0.id == id }
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
        task(for: run.taskID)?.title ?? "Deleted Task"
    }

    func pomodoroRemainingSeconds(for run: PomodoroRun, now: Date = Date()) -> Int {
        guard run.state == .focusing, let startedAt = run.startedAt else {
            return run.focusSecondsPlanned
        }
        return max(0, run.focusSecondsPlanned - Int(now.timeIntervalSince(startedAt)))
    }

    func pomodoroProgress(for run: PomodoroRun, now: Date = Date()) -> Double {
        guard run.focusSecondsPlanned > 0 else { return 0 }
        let remaining = pomodoroRemainingSeconds(for: run, now: now)
        return min(1, max(0, 1 - Double(remaining) / Double(run.focusSecondsPlanned)))
    }

    func pomodoroStateLabel(for run: PomodoroRun) -> String {
        switch run.state {
        case .planned:
            return "Ready"
        case .focusing:
            return "Focus"
        case .shortBreak:
            return "Short Break"
        case .longBreak:
            return "Long Break"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        case .interrupted:
            return "Interrupted"
        }
    }

    func path(for task: TaskNode) -> String {
        var names = [task.title]
        var cursor = task.parentID
        while let parentID = cursor, let parent = self.task(for: parentID) {
            names.insert(parent.title, at: 0)
            cursor = parent.parentID
        }
        return names.joined(separator: " / ")
    }

    func displayTitle(for segment: TimeSegment) -> String {
        task(for: segment.taskID)?.title ?? "Deleted Task"
    }

    func displayPath(for segment: TimeSegment) -> String {
        guard let task = task(for: segment.taskID) else { return "Ledger" }
        var parents: [String] = []
        var cursor = task.parentID
        while let parentID = cursor, let parent = self.task(for: parentID) {
            parents.insert(parent.title, at: 0)
            cursor = parent.parentID
        }
        return parents.joined(separator: " / ")
    }

    func note(for segment: TimeSegment) -> String {
        sessions.first { $0.id == segment.sessionID }?.note ?? ""
    }

    func secondsForTaskToday(_ task: TaskNode, mode: AggregationMode = .gross) -> Int {
        aggregationService.totalSeconds(segments: todaySegments.filter { $0.taskID == task.id }, mode: mode)
    }

    func secondsForTaskThisWeek(_ task: TaskNode, mode: AggregationMode = .gross, now: Date = Date()) -> Int {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        let segments = allSegments.filter { $0.taskID == task.id && overlaps($0, interval: interval, now: now) }
        return aggregationService.totalSeconds(segments: segments, mode: mode, now: now)
    }

    func recentSegments(for task: TaskNode, limit: Int = 6) -> [TimeSegment] {
        allSegments
            .filter { $0.taskID == task.id && $0.deletedAt == nil }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit)
            .map { $0 }
    }

    func analyticsOverview(for range: AnalyticsRange, now: Date = Date()) -> AnalyticsOverview {
        let segments = segmentsForAnalytics(range: range, now: now)
        let gross = aggregationService.totalSeconds(segments: segments, mode: .gross, now: now)
        let wall = aggregationService.totalSeconds(segments: segments, mode: .wallClock, now: now)
        let pomodoros = segments.filter { $0.source == .pomodoro && $0.endedAt != nil }.count
        let focusSegments = segments.filter { $0.source == .pomodoro }
        let averageFocus = focusSegments.isEmpty ? 0 : aggregationService.grossSeconds(focusSegments, now: now) / focusSegments.count
        return AnalyticsOverview(
            grossSeconds: gross,
            wallSeconds: wall,
            overlapSeconds: max(0, gross - wall),
            pomodoroCount: pomodoros,
            averageFocusSeconds: averageFocus
        )
    }

    func dailyBreakdown(range: AnalyticsRange, now: Date = Date()) -> [DailyAnalyticsPoint] {
        let calendar = Calendar.current
        return dayIntervals(for: range, now: now).map { interval in
            let segments = allSegments.filter { overlaps($0, interval: interval, now: now) }
            return DailyAnalyticsPoint(
                date: interval.start,
                grossSeconds: aggregationService.totalSeconds(segments: segments, mode: .gross, now: now),
                wallSeconds: aggregationService.totalSeconds(segments: segments, mode: .wallClock, now: now),
                label: calendar.shortWeekdaySymbols[calendar.component(.weekday, from: interval.start) - 1]
            )
        }
    }

    func hourlyBreakdown(for date: Date = Date(), now: Date = Date()) -> [HourlyAnalyticsPoint] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        return (0..<24).map { hour in
            let start = calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
            let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3_600)
            let interval = DateInterval(start: start, end: end)
            let segments = allSegments.filter { overlaps($0, interval: interval, now: now) }
            let gross = secondsOverlapping(segments: segments, interval: interval, now: now)
            let wallIntervals = segments.compactMap { clippedInterval(for: $0, in: interval, now: now) }
            let wall = aggregationService.mergeOverlappingIntervals(wallIntervals).reduce(0) {
                $0 + Int($1.end.timeIntervalSince($1.start))
            }
            return HourlyAnalyticsPoint(hour: hour, grossSeconds: gross, wallSeconds: wall)
        }
    }

    func taskBreakdown(range: AnalyticsRange, now: Date = Date()) -> [TaskAnalyticsPoint] {
        let segments = segmentsForAnalytics(range: range, now: now)
        let grouped = Dictionary(grouping: segments, by: \.taskID)
        return grouped.compactMap { taskID, taskSegments -> TaskAnalyticsPoint? in
            let gross = aggregationService.totalSeconds(segments: taskSegments, mode: .gross, now: now)
            guard gross > 0 else { return nil }
            let task = task(for: taskID)
            let fallbackTitle = sessions.first { $0.taskID == taskID }?.titleSnapshot ?? "已删除任务"
            return TaskAnalyticsPoint(
                taskID: taskID,
                title: task?.title ?? fallbackTitle,
                path: task.map { path(for: $0) } ?? "历史账本 / 已删除任务",
                colorHex: task?.colorHex,
                grossSeconds: gross,
                wallSeconds: aggregationService.totalSeconds(segments: taskSegments, mode: .wallClock, now: now)
            )
        }
        .sorted { $0.grossSeconds > $1.grossSeconds }
    }

    func overlapSegments(range: AnalyticsRange, now: Date = Date()) -> [OverlapAnalyticsPoint] {
        let segments = segmentsForAnalytics(range: range, now: now)
            .filter { $0.endedAt != nil || $0.startedAt <= now }
            .sorted { $0.startedAt < $1.startedAt }

        var overlaps: [OverlapAnalyticsPoint] = []
        for index in segments.indices {
            for otherIndex in segments.index(after: index)..<segments.endIndex {
                let first = segments[index]
                let second = segments[otherIndex]
                let firstEnd = first.endedAt ?? now
                let secondEnd = second.endedAt ?? now
                let start = max(first.startedAt, second.startedAt)
                let end = min(firstEnd, secondEnd)
                if end > start {
                    overlaps.append(
                        OverlapAnalyticsPoint(
                            start: start,
                            end: end,
                            firstTitle: displayTitle(for: first),
                            secondTitle: displayTitle(for: second)
                        )
                    )
                }
            }
        }
        return overlaps.sorted { $0.durationSeconds > $1.durationSeconds }
    }

    func rootTasks() -> [TaskNode] {
        tasks.filter { $0.parentID == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func children(of task: TaskNode) -> [TaskNode] {
        tasks.filter { $0.parentID == task.id }.sorted { $0.sortOrder < $1.sortOrder }
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

    private func dayIntervals(for range: AnalyticsRange, now: Date) -> [DateInterval] {
        let calendar = Calendar.current
        guard let interval = analyticsInterval(for: range, now: now) else { return [] }
        var result: [DateInterval] = []
        var cursor = interval.start
        while cursor < interval.end {
            let next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? interval.end
            result.append(DateInterval(start: cursor, end: min(next, interval.end)))
            cursor = next
        }
        return result
    }

    private func overlaps(_ segment: TimeSegment, interval: DateInterval, now: Date) -> Bool {
        let end = segment.endedAt ?? now
        return segment.startedAt < interval.end && end > interval.start
    }

    private func clippedInterval(for segment: TimeSegment, in interval: DateInterval, now: Date) -> DateInterval? {
        guard segment.deletedAt == nil else { return nil }
        let end = segment.endedAt ?? now
        let start = max(segment.startedAt, interval.start)
        let clippedEnd = min(end, interval.end)
        guard clippedEnd > start else { return nil }
        return DateInterval(start: start, end: clippedEnd)
    }

    private func secondsOverlapping(segments: [TimeSegment], interval: DateInterval, now: Date) -> Int {
        segments.reduce(0) { result, segment in
            guard let clipped = clippedInterval(for: segment, in: interval, now: now) else { return result }
            return result + Int(clipped.end.timeIntervalSince(clipped.start))
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
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
                    store.refreshQuietly()
                }
            }
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
        run.startedAt = Date()
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

    private func fetchCountdownEvents() throws -> [CountdownEvent] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<CountdownEvent>(
            sortBy: [
                SortDescriptor(\.date),
                SortDescriptor(\.createdAt)
            ]
        )
        return try modelContext.fetch(descriptor).filter { $0.deletedAt == nil }
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
    var kind: TaskNodeKind
    var status: TaskStatus
    var parentID: UUID?
    var colorHex: String
    var iconName: String
    var notes: String
    var estimatedMinutes: Int?
    var hasDueDate: Bool
    var dueAt: Date

    init(parentID: UUID?) {
        self.taskID = nil
        self.title = ""
        self.kind = .task
        self.status = .active
        self.parentID = parentID
        self.colorHex = "1677FF"
        self.iconName = "checkmark.circle"
        self.notes = ""
        self.estimatedMinutes = nil
        self.hasDueDate = false
        self.dueAt = Date()
    }

    init(task: TaskNode) {
        self.taskID = task.id
        self.title = task.title
        self.kind = task.kind
        self.status = task.status
        self.parentID = task.parentID
        self.colorHex = task.colorHex ?? "1677FF"
        self.iconName = task.iconName ?? "checkmark.circle"
        self.notes = task.notes ?? ""
        self.estimatedMinutes = task.estimatedSeconds.map { $0 / 60 }
        self.hasDueDate = task.dueAt != nil
        self.dueAt = task.dueAt ?? Date()
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
}

struct AnalyticsOverview {
    let grossSeconds: Int
    let wallSeconds: Int
    let overlapSeconds: Int
    let pomodoroCount: Int
    let averageFocusSeconds: Int
}

struct DailyAnalyticsPoint: Identifiable {
    let id = UUID()
    let date: Date
    let grossSeconds: Int
    let wallSeconds: Int
    let label: String
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
    let grossSeconds: Int
    let wallSeconds: Int

    var id: UUID { taskID }
}

struct OverlapAnalyticsPoint: Identifiable {
    let id = UUID()
    let start: Date
    let end: Date
    let firstTitle: String
    let secondTitle: String

    var durationSeconds: Int {
        max(0, Int(end.timeIntervalSince(start)))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
