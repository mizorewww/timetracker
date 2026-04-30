import Foundation
import SwiftData

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

enum AggregationMode: String, CaseIterable, Identifiable {
    case gross
    case wallClock

    var id: String { rawValue }
}

extension TimeSessionSource {
    var displayName: String {
        switch self {
        case .manual:
            return AppStrings.localized("source.manual")
        case .timer:
            return AppStrings.localized("source.timer")
        case .pomodoro:
            return AppStrings.pomodoro
        case .importCalendar:
            return AppStrings.localized("source.calendar")
        case .shortcut:
            return AppStrings.localized("source.shortcut")
        case .watch:
            return AppStrings.localized("source.watch")
        case .widget:
            return AppStrings.localized("source.widget")
        case .liveActivity:
            return AppStrings.localized("source.liveActivity")
        }
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

extension TimeSegment {
    var source: TimeSessionSource {
        TimeSessionSource(rawValue: sourceRaw) ?? .timer
    }

    var isActive: Bool {
        endedAt == nil && deletedAt == nil
    }
}
