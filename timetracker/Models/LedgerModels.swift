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

nonisolated enum AggregationMode: String, CaseIterable, Identifiable {
    case gross
    case wallClock

    var id: String {
        rawValue
    }
}

/// The single boundary policy for persisted tracked time.
///
/// Local write paths reject future records, but CloudKit, imports, and legacy
/// stores can still contain clock-skewed values. Every read path therefore
/// clips an interval to its reference date instead of trusting `endedAt`.
nonisolated enum TrackedTimePolicy {
    enum WriteValidation: Equatable {
        case valid
        case invalidRange
        case futureTime
    }

    static func boundedEnd(endedAt: Date?, now: Date) -> Date {
        min(endedAt ?? now, now)
    }

    static func interval(
        startedAt: Date,
        endedAt: Date?,
        now: Date,
        clippedTo bounds: DateInterval? = nil
    ) -> DateInterval? {
        let start = max(startedAt, bounds?.start ?? startedAt)
        let end = min(boundedEnd(endedAt: endedAt, now: now), bounds?.end ?? now)
        guard start < now, end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func elapsedSeconds(startedAt: Date, endedAt: Date?, now: Date) -> Int {
        interval(startedAt: startedAt, endedAt: endedAt, now: now)
            .map { max(0, Int($0.duration)) } ?? 0
    }

    static func overlaps(
        startedAt: Date,
        endedAt: Date?,
        interval: DateInterval,
        now: Date
    ) -> Bool {
        self.interval(
            startedAt: startedAt,
            endedAt: endedAt,
            now: now,
            clippedTo: interval
        ) != nil
    }

    static func validateWrite(startedAt: Date, endedAt: Date?, now: Date) -> WriteValidation {
        if let endedAt {
            guard endedAt > startedAt else { return .invalidRange }
            guard endedAt <= now else { return .futureTime }
            return .valid
        }
        return startedAt > now ? .futureTime : .valid
    }
}

extension TimeSessionSource {
    var displayName: String {
        switch self {
        case .manual:
            AppStrings.localized("source.manual")
        case .timer:
            AppStrings.localized("source.timer")
        case .pomodoro:
            AppStrings.pomodoro
        case .importCalendar:
            AppStrings.localized("source.calendar")
        case .shortcut:
            AppStrings.localized("source.shortcut")
        case .watch:
            AppStrings.localized("source.watch")
        case .widget:
            AppStrings.localized("source.widget")
        case .liveActivity:
            AppStrings.localized("source.liveActivity")
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
        id = UUID()
        self.taskID = taskID
        self.titleSnapshot = titleSnapshot
        sourceRaw = source.rawValue
        self.startedAt = startedAt
        self.deviceID = deviceID
        clientMutationID = UUID()
        createdAt = Date()
        updatedAt = Date()
    }
}

extension TimeSession {
    /// Refreshes the conflict metadata together with every persisted content
    /// mutation so equal-timestamp CloudKit conflicts represent the latest
    /// writer rather than the device that originally created the session.
    func markMutated(at date: Date, deviceID: String) {
        updatedAt = date
        self.deviceID = deviceID
        clientMutationID = UUID()
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
        id = UUID()
        self.sessionID = sessionID
        self.taskID = taskID
        self.startedAt = startedAt
        self.endedAt = endedAt
        sourceRaw = source.rawValue
        self.deviceID = deviceID
        createdAt = Date()
        updatedAt = Date()
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
