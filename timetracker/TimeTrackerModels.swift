import Foundation
import SwiftData

enum TaskNodeKind: String, Codable, CaseIterable, Identifiable {
    case folder
    case project
    case task

    var id: String { rawValue }
}

enum TaskStatus: String, Codable, CaseIterable {
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
    var id: UUID
    var title: String
    var kindRaw: String
    var parentID: UUID?
    var sortOrder: Double
    var path: String
    var depth: Int
    var statusRaw: String
    var colorHex: String?
    var iconName: String?
    var estimatedSeconds: Int?
    var dueAt: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var deletedAt: Date?
    var deviceID: String
    var clientMutationID: UUID

    init(
        title: String,
        kind: TaskNodeKind,
        parentID: UUID?,
        deviceID: String,
        colorHex: String? = nil,
        iconName: String? = nil,
        sortOrder: Double = 0
    ) {
        self.id = UUID()
        self.title = title
        self.kindRaw = kind.rawValue
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
    var id: UUID
    var taskID: UUID
    var titleSnapshot: String?
    var sourceRaw: String
    var startedAt: Date
    var endedAt: Date?
    var note: String?
    var deviceID: String
    var clientMutationID: UUID
    var createdAt: Date
    var updatedAt: Date
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
    var id: UUID
    var sessionID: UUID
    var taskID: UUID
    var startedAt: Date
    var endedAt: Date?
    var sourceRaw: String
    var deviceID: String
    var createdAt: Date
    var updatedAt: Date
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
    var id: UUID
    var taskID: UUID
    var sessionID: UUID?
    var focusSecondsPlanned: Int
    var breakSecondsPlanned: Int
    var longBreakSecondsPlanned: Int?
    var stateRaw: String
    var startedAt: Date?
    var endedAt: Date?
    var completedFocusRounds: Int
    var targetRounds: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var deviceID: String
    var clientMutationID: UUID

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
    var id: UUID
    var date: Date
    var taskID: UUID?
    var grossSeconds: Int
    var wallClockSeconds: Int
    var pomodoroCount: Int
    var interruptionCount: Int
    var generatedAt: Date
    var version: Int

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

enum TimeTrackerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TimeTrackerSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

extension TaskNode {
    var kind: TaskNodeKind {
        get { TaskNodeKind(rawValue: kindRaw) ?? .task }
        set { kindRaw = newValue.rawValue }
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var isRunning: Bool {
        status == .paused ? false : false
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
