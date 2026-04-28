import Foundation
import SwiftData

enum TaskStatus: String, Codable, CaseIterable {
    case planned
    case active
    case paused
    case completed
    case archived
}

enum TimeSessionSource: String, Codable, CaseIterable {
    case manual
    case timer
    case pomodoro
    case importCalendar
    case shortcut
    case watch
    case widget
    case liveActivity
}

enum PomodoroState: String, Codable, CaseIterable {
    case planned
    case focusing
    case shortBreak
    case longBreak
    case completed
    case cancelled
    case interrupted
}

enum AggregationMode: String, CaseIterable, Identifiable {
    case gross
    case wallClock

    var id: String { rawValue }
}

@Model
final class TaskNode {
    var id: UUID = UUID()
    var title: String = ""
    var kindRaw: String = "task"
    var parentID: UUID?
    var sortOrder: Double = 0
    var path: String = ""
    var depth: Int = 0
    var statusRaw: String = TaskStatus.active.rawValue
    var colorHex: String?
    var iconName: String?
    var estimatedSeconds: Int?
    var dueAt: Date?
    var notes: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var archivedAt: Date?
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        title: String,
        parentID: UUID?,
        deviceID: String,
        colorHex: String? = nil,
        iconName: String? = nil,
        sortOrder: Double = 0
    ) {
        self.id = UUID()
        self.title = title
        self.parentID = parentID
        self.sortOrder = sortOrder
        self.path = ""
        self.depth = 0
        self.statusRaw = TaskStatus.active.rawValue
        self.colorHex = colorHex
        self.iconName = iconName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deviceID = deviceID
        self.clientMutationID = UUID()
    }
}

@Model
final class TimeSession {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var titleSnapshot: String?
    var sourceRaw: String = TimeSessionSource.timer.rawValue
    var startedAt: Date = Date()
    var endedAt: Date?
    var note: String?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        taskID: UUID,
        source: TimeSessionSource,
        deviceID: String,
        startedAt: Date = Date(),
        titleSnapshot: String? = nil
    ) {
        self.id = UUID()
        self.taskID = taskID
        self.titleSnapshot = titleSnapshot
        self.sourceRaw = source.rawValue
        self.startedAt = startedAt
        self.deviceID = deviceID
        self.clientMutationID = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class TimeSegment {
    var id: UUID = UUID()
    var sessionID: UUID = UUID()
    var taskID: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var sourceRaw: String = TimeSessionSource.timer.rawValue
    var deviceID: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?

    init(
        sessionID: UUID,
        taskID: UUID,
        source: TimeSessionSource,
        deviceID: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil
    ) {
        self.id = UUID()
        self.sessionID = sessionID
        self.taskID = taskID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceRaw = source.rawValue
        self.deviceID = deviceID
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

@Model
final class PomodoroRun {
    var id: UUID = UUID()
    var taskID: UUID = UUID()
    var sessionID: UUID?
    var focusSecondsPlanned: Int = 25 * 60
    var breakSecondsPlanned: Int = 5 * 60
    var longBreakSecondsPlanned: Int?
    var stateRaw: String = PomodoroState.planned.rawValue
    var startedAt: Date?
    var endedAt: Date?
    var completedFocusRounds: Int = 0
    var targetRounds: Int = 1
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        taskID: UUID,
        focus: Int = 25 * 60,
        breakSeconds: Int = 5 * 60,
        targetRounds: Int = 1,
        deviceID: String
    ) {
        self.id = UUID()
        self.taskID = taskID
        self.focusSecondsPlanned = focus
        self.breakSecondsPlanned = breakSeconds
        self.stateRaw = PomodoroState.planned.rawValue
        self.completedFocusRounds = 0
        self.targetRounds = targetRounds
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deviceID = deviceID
        self.clientMutationID = UUID()
    }
}

@Model
final class DailySummary {
    var id: UUID = UUID()
    var date: Date = Date()
    var taskID: UUID?
    var grossSeconds: Int = 0
    var wallClockSeconds: Int = 0
    var pomodoroCount: Int = 0
    var interruptionCount: Int = 0
    var generatedAt: Date = Date()
    var version: Int = 1

    init(date: Date, taskID: UUID?, grossSeconds: Int, wallClockSeconds: Int, pomodoroCount: Int, interruptionCount: Int, version: Int = 1) {
        self.id = UUID()
        self.date = date
        self.taskID = taskID
        self.grossSeconds = grossSeconds
        self.wallClockSeconds = wallClockSeconds
        self.pomodoroCount = pomodoroCount
        self.interruptionCount = interruptionCount
        self.generatedAt = Date()
        self.version = version
    }
}

@Model
final class CountdownEvent {
    var id: UUID = UUID()
    var title: String = ""
    var date: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        title: String,
        date: Date,
        deviceID: String
    ) {
        self.id = UUID()
        self.title = title
        self.date = date
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deviceID = deviceID
        self.clientMutationID = UUID()
    }
}

enum TimeTrackerSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self
        ]
    }
}

enum TimeTrackerSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self
        ]
    }
}

enum TimeTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TimeTrackerSchemaV1.self, TimeTrackerSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: TimeTrackerSchemaV1.self, toVersion: TimeTrackerSchemaV2.self)
        ]
    }
}

extension TaskNode {
    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var isRunning: Bool {
        status == .paused ? false : false
    }
}

extension TaskStatus {
    static var editableCases: [TaskStatus] {
        [.planned, .active, .completed]
    }

    var displayName: String {
        switch self {
        case .planned: return AppStrings.localized("status.planned")
        case .active: return AppStrings.localized("status.active")
        case .paused: return AppStrings.paused
        case .completed: return AppStrings.localized("status.completed")
        case .archived: return AppStrings.localized("status.archived")
        }
    }

    var exampleText: String {
        switch self {
        case .planned: return AppStrings.localized("editor.task.status.planned.example")
        case .active: return AppStrings.localized("editor.task.status.active.example")
        case .paused: return AppStrings.paused
        case .completed: return AppStrings.localized("editor.task.status.completed.example")
        case .archived: return AppStrings.localized("status.archived")
        }
    }

    var symbolName: String {
        switch self {
        case .planned: return "calendar"
        case .active: return "circle"
        case .paused: return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .archived: return "archivebox"
        }
    }

    var colorHex: String {
        switch self {
        case .planned: return "0EA5E9"
        case .active: return "64748B"
        case .paused: return "F97316"
        case .completed: return "16A34A"
        case .archived: return "64748B"
        }
    }
}

extension TimeSegment {
    var source: TimeSessionSource {
        TimeSessionSource(rawValue: sourceRaw) ?? .timer
    }

    var isActive: Bool {
        endedAt == nil && deletedAt == nil
    }
}

extension PomodoroRun {
    var state: PomodoroState {
        get { PomodoroState(rawValue: stateRaw) ?? .planned }
        set { stateRaw = newValue.rawValue }
    }
}
