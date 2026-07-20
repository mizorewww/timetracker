import Foundation
import SwiftData

nonisolated enum TaskRecurrenceCadence: String, CaseIterable, Codable {
    case daily
}

nonisolated enum TaskRecurrencePolicy {
    static let maximumTimeZoneIdentifierByteCount = 128
}

nonisolated enum TaskRecurrenceDayKey {
    static func isCanonical(_ value: String) -> Bool {
        guard value.utf8.count == 10,
              value.utf8.allSatisfy({
                  (48...57).contains($0) || $0 == 45
              }) else {
            return false
        }
        let parts = value.split(
            separator: "-",
            omittingEmptySubsequences: false
        )
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            return false
        }
        let resolved = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return resolved.year == year &&
            resolved.month == month &&
            resolved.day == day
    }
}

@Model
final class TaskRecurrenceRule {
    var id: UUID = UUID()
    var templateTaskID: UUID = UUID()
    var cadenceRaw: String = TaskRecurrenceCadence.daily.rawValue
    var startDayKey: String = ""
    var timeZoneIdentifier: String = "UTC"
    var isEnabled: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        templateTaskID: UUID,
        startDayKey: String,
        timeZoneIdentifier: String,
        cadence: TaskRecurrenceCadence = .daily,
        deviceID: String
    ) {
        id = TaskProgressIdentity.recurrenceRuleID(
            templateTaskID: templateTaskID
        )
        self.templateTaskID = templateTaskID
        cadenceRaw = cadence.rawValue
        self.startDayKey = startDayKey
        self.timeZoneIdentifier = timeZoneIdentifier
        isEnabled = true
        self.deviceID = deviceID
    }
}

@Model
final class TaskRecurrenceOccurrence {
    var id: UUID = UUID()
    var ruleID: UUID = UUID()
    var templateTaskID: UUID = UUID()
    var occurrenceDayKey: String = ""
    var timeZoneIdentifier: String = "UTC"
    var generatedTaskID: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        ruleID: UUID,
        templateTaskID: UUID,
        occurrenceDayKey: String,
        timeZoneIdentifier: String,
        deviceID: String
    ) {
        id = TaskProgressIdentity.recurrenceOccurrenceID(
            ruleID: ruleID,
            dayKey: occurrenceDayKey
        )
        self.ruleID = ruleID
        self.templateTaskID = templateTaskID
        self.occurrenceDayKey = occurrenceDayKey
        self.timeZoneIdentifier = timeZoneIdentifier
        generatedTaskID = TaskProgressIdentity.generatedTaskID(
            ruleID: ruleID,
            dayKey: occurrenceDayKey
        )
        self.deviceID = deviceID
    }
}
