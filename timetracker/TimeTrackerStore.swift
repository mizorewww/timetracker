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
            selectedTaskID = activeSegments.first?.taskID ?? tasks.first(where: { $0.kind != .folder })?.id ?? tasks.first?.id
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

    func createQuickTask() {
        perform {
            let title = "新建任务"
            let parentID = tasks.first(where: { $0.title == "Time Tracker App" })?.id
            let task = try CreateTaskUseCase(repository: requiredTaskRepository()).execute(
                title: title,
                kind: .task,
                parentID: parentID,
                colorHex: "1677FF",
                iconName: "plus"
            )
            selectedTaskID = task.id
        }
    }

    func addManualTimeForSelectedTask() {
        guard let selectedTaskID else { return }
        perform {
            let end = Date()
            let start = end.addingTimeInterval(-30 * 60)
            _ = try AddManualTimeUseCase(repository: requiredTimeRepository()).execute(
                taskID: selectedTaskID,
                startedAt: start,
                endedAt: end,
                note: "Manual"
            )
        }
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
        tasks.filter { $0.kind != .folder && $0.status == .active }.prefix(4).map { $0 }
    }

    var timelineSegments: [TimeSegment] {
        todaySegments.sorted { $0.startedAt > $1.startedAt }
    }

    var todayGrossSeconds: Int {
        aggregationService.totalSeconds(segments: todaySegments, mode: .gross)
    }

    var todayWallSeconds: Int {
        aggregationService.totalSeconds(segments: todaySegments, mode: .wallClock)
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
