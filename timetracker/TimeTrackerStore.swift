import Combine
import Foundation
import SwiftData

@MainActor
final class TimeTrackerStore: ObservableObject {
    @Published private(set) var tasks: [TaskNode] = []
    @Published private(set) var activeSegments: [TimeSegment] = []
    @Published private(set) var todaySegments: [TimeSegment] = []
    @Published private(set) var sessions: [TimeSession] = []
    @Published var selectedTaskID: UUID?
    @Published var selectedRange: RangePreset = .today
    @Published var errorMessage: String?
    @Published var taskEditorDraft: TaskEditorDraft?
    @Published var manualTimeDraft: ManualTimeDraft?

    enum RangePreset: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "Week"
        case month = "Month"

        var id: String { rawValue }
    }

    private var taskRepository: TaskRepository?
    private var timeRepository: TimeTrackingRepository?
    private var pomodoroRepository: PomodoroRepository?
    private let aggregationService = TimeAggregationService()

    func configureIfNeeded(context: ModelContext) {
        guard taskRepository == nil else { return }
        let taskRepository = SwiftDataTaskRepository(context: context)
        let timeRepository = SwiftDataTimeTrackingRepository(context: context)
        self.taskRepository = taskRepository
        self.timeRepository = timeRepository
        self.pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository)

        do {
            try SeedData.ensureSeeded(context: context)
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() throws {
        guard let taskRepository, let timeRepository else { return }
        tasks = try taskRepository.allNodes()
        activeSegments = try timeRepository.activeSegments()
        sessions = try timeRepository.sessions()

        let range = Calendar.current.dateInterval(of: .day, for: Date()) ?? DateInterval(start: Date(), duration: 24 * 60 * 60)
        todaySegments = try timeRepository.segments(from: range.start, to: range.end)

        if selectedTaskID == nil {
            selectedTaskID = activeSegments.first?.taskID ?? tasks.first?.id
        }
    }

    func startSelectedTask() {
        guard let selectedTaskID else { return }
        perform {
            _ = try StartTaskUseCase(repository: requiredTimeRepository()).execute(taskID: selectedTaskID, source: .timer)
        }
    }

    func startTask(_ task: TaskNode) {
        selectedTaskID = task.id
        perform {
            _ = try StartTaskUseCase(repository: requiredTimeRepository()).execute(taskID: task.id, source: .timer)
        }
    }

    func stop(segment: TimeSegment) {
        perform {
            try StopSegmentUseCase(repository: requiredTimeRepository()).execute(segmentID: segment.id)
        }
    }

    func pause(segment: TimeSegment) {
        perform {
            try PauseSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: segment.sessionID)
        }
    }

    func resume(session: TimeSession) {
        perform {
            _ = try ResumeSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: session.id)
        }
    }

    func stop(session: TimeSession) {
        perform {
            try StopSessionUseCase(repository: requiredTimeRepository()).execute(sessionID: session.id)
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

    func startPomodoroForSelectedTask() {
        guard let selectedTaskID else { return }
        perform {
            _ = try StartPomodoroUseCase(repository: requiredPomodoroRepository()).execute(taskID: selectedTaskID)
        }
    }

    var selectedTask: TaskNode? {
        guard let selectedTaskID else { return nil }
        return task(for: selectedTaskID)
    }

    var recentTasks: [TaskNode] {
        tasks.filter { $0.status == .active }.prefix(4).map { $0 }
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
        todaySegments.filter { $0.source == .pomodoro && $0.endedAt != nil }.count
    }

    var averageFocusSeconds: Int {
        let focus = todaySegments.filter { $0.source == .pomodoro }
        guard !focus.isEmpty else { return 0 }
        return aggregationService.grossSeconds(focus) / focus.count
    }

    func task(for id: UUID) -> TaskNode? {
        tasks.first { $0.id == id }
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

    func secondsForTaskToday(_ task: TaskNode, mode: AggregationMode = .gross) -> Int {
        aggregationService.totalSeconds(segments: todaySegments.filter { $0.taskID == task.id }, mode: mode)
    }

    func rootTasks() -> [TaskNode] {
        tasks.filter { $0.parentID == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func children(of task: TaskNode) -> [TaskNode] {
        tasks.filter { $0.parentID == task.id }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            try refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
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
}

struct TaskEditorDraft: Identifiable {
    let id = UUID()
    var taskID: UUID?
    var title: String
    var kind: TaskNodeKind
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
