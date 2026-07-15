import Foundation
import SwiftData

enum PomodoroState: String, Codable, CaseIterable {
    case planned
    case focusing
    case shortBreak
    case longBreak
    case completed
    case cancelled
    case interrupted
}

struct PomodoroPlan: Identifiable, Codable, Equatable {
    static let minuteOptions = Array(stride(from: 5, through: 60, by: 5))
    static let roundRange = 1...24
    private static let classicPlanID = UUID(uuidString: "E5CEB875-7D85-45B5-91E9-CA263F08BBF6")!
    private static let deepWorkPlanID = UUID(uuidString: "6272DC5F-D683-486F-BF36-29C439746C98")!
    private static let quickStartPlanID = UUID(uuidString: "7D2C2A71-FA5C-474A-8D5D-4CD4D5C7668B")!

    var id: UUID
    var name: String
    var iconName: String
    var colorHex: String
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var rounds: Int

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "timer",
        colorHex: String = "FF2D55",
        focusMinutes: Int = 25,
        shortBreakMinutes: Int = 5,
        longBreakMinutes: Int = 15,
        rounds: Int = 4
    ) {
        self.id = id
        self.name = AppPreferenceValueSanitizer.pomodoroPlanName(name)
        self.iconName = ChecklistVisualSanitizer.sanitizedIcon(iconName)
        self.colorHex = ChecklistVisualSanitizer.sanitizedColor(colorHex, fallback: "FF2D55")
        self.focusMinutes = Self.normalizedMinute(focusMinutes)
        self.shortBreakMinutes = Self.normalizedMinute(shortBreakMinutes)
        self.longBreakMinutes = Self.normalizedMinute(longBreakMinutes)
        self.rounds = rounds.clamped(to: Self.roundRange)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = AppPreferenceValueSanitizer.pomodoroPlanName(
            try container.decodeIfPresent(String.self, forKey: .name)
                ?? AppStrings.localized("pomodoro.untitledPlan")
        )
        iconName = ChecklistVisualSanitizer.sanitizedIcon(try container.decodeIfPresent(String.self, forKey: .iconName))
        colorHex = ChecklistVisualSanitizer.sanitizedColor(
            try container.decodeIfPresent(String.self, forKey: .colorHex),
            fallback: "FF2D55"
        )
        focusMinutes = Self.normalizedMinute(try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25)
        shortBreakMinutes = Self.normalizedMinute(try container.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5)
        longBreakMinutes = Self.normalizedMinute(try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 15)
        rounds = (try container.decodeIfPresent(Int.self, forKey: .rounds) ?? 4).clamped(to: Self.roundRange)
    }

    var focusSeconds: Int { focusMinutes * 60 }
    var shortBreakSeconds: Int { shortBreakMinutes * 60 }
    var longBreakSeconds: Int { longBreakMinutes * 60 }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppStrings.localized("pomodoro.untitledPlan") : trimmed
    }

    func normalized() -> PomodoroPlan {
        PomodoroPlan(
            id: id,
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            focusMinutes: focusMinutes,
            shortBreakMinutes: shortBreakMinutes,
            longBreakMinutes: longBreakMinutes,
            rounds: rounds
        )
    }

    static var defaultPlans: [PomodoroPlan] {
        [
            PomodoroPlan(
                id: classicPlanID,
                name: AppStrings.localized("pomodoro.preset.classic"),
                iconName: "timer",
                colorHex: "FF2D55",
                focusMinutes: 25,
                shortBreakMinutes: 5,
                longBreakMinutes: 15,
                rounds: 4
            ),
            PomodoroPlan(
                id: deepWorkPlanID,
                name: AppStrings.localized("pomodoro.preset.deep"),
                iconName: "target",
                colorHex: "5E5CE6",
                focusMinutes: 50,
                shortBreakMinutes: 10,
                longBreakMinutes: 20,
                rounds: 3
            ),
            PomodoroPlan(
                id: quickStartPlanID,
                name: AppStrings.localized("pomodoro.preset.quick"),
                iconName: "clock",
                colorHex: "FF9F0A",
                focusMinutes: 15,
                shortBreakMinutes: 5,
                longBreakMinutes: 10,
                rounds: 2
            )
        ]
    }

    static var newPlan: PomodoroPlan {
        PomodoroPlan(name: AppStrings.localized("pomodoro.newPlan"))
    }

    static func normalizedMinute(_ value: Int) -> Int {
        let clamped = value.clamped(to: 5...60)
        let rounded = Int((Double(clamped) / 5.0).rounded()) * 5
        return rounded.clamped(to: 5...60)
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
        longBreakSeconds: Int? = nil,
        targetRounds: Int = 1,
        deviceID: String
    ) {
        self.id = UUID()
        self.taskID = taskID
        self.focusSecondsPlanned = focus
        self.breakSecondsPlanned = breakSeconds
        self.longBreakSecondsPlanned = longBreakSeconds
        self.stateRaw = PomodoroState.planned.rawValue
        self.completedFocusRounds = 0
        self.targetRounds = targetRounds
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deviceID = deviceID
        self.clientMutationID = UUID()
    }
}

extension PomodoroRun {
    var state: PomodoroState {
        get { PomodoroState(rawValue: stateRaw) ?? .planned }
        set { stateRaw = newValue.rawValue }
    }

    /// The current phase deadline is derived from persisted phase state instead
    /// of a view-owned timer. `startedAt` intentionally means the start of the
    /// active focus or break phase.
    var phaseDeadline: Date? {
        guard deletedAt == nil, endedAt == nil else { return nil }
        let duration: Int
        switch state {
        case .focusing, .interrupted:
            duration = focusSecondsPlanned
        case .shortBreak:
            duration = breakSecondsPlanned
        case .longBreak:
            duration = longBreakSecondsPlanned ?? breakSecondsPlanned
        case .planned, .completed, .cancelled:
            return nil
        }
        let phaseStartedAt = startedAt ?? updatedAt
        return phaseStartedAt.addingTimeInterval(TimeInterval(max(1, duration)))
    }

    func phaseHasExpired(at date: Date) -> Bool {
        guard let phaseDeadline else { return false }
        return date >= phaseDeadline
    }

    /// Applies the shared focus-to-break/completed state transition after the
    /// caller has bounded the associated ledger session to `endedAt`.
    func completeFocusPhase(endedAt: Date, mutationDate: Date, deviceID: String) {
        guard state == .focusing || state == .interrupted else { return }
        completedFocusRounds += 1
        let didComplete = completedFocusRounds >= targetRounds
        state = didComplete
            ? .completed
            : (completedFocusRounds.isMultiple(of: 4) ? .longBreak : .shortBreak)
        sessionID = nil
        startedAt = didComplete ? startedAt : endedAt
        self.endedAt = didComplete ? endedAt : nil
        markMutated(at: mutationDate, deviceID: deviceID)
    }

    /// Keeps the sync conflict tuple aligned with the writer that performed a
    /// local state transition. Call this after changing any persisted run field.
    func markMutated(at mutationDate: Date, deviceID: String) {
        updatedAt = mutationDate
        self.deviceID = deviceID
        clientMutationID = UUID()
    }
}
