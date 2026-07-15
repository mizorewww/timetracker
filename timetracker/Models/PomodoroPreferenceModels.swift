import Foundation

/// Stable preference values for the built-in Pomodoro timing presets.
///
/// This model intentionally contains no SwiftUI or localized presentation
/// concerns so persistence can depend on it without importing a feature view.
nonisolated enum PomodoroPreset: String, CaseIterable, Identifiable, Sendable {
    case classic = "25 / 5"
    case deep = "50 / 10"
    case quick = "15 / 3"
    case custom = "custom"

    var id: String { rawValue }

    var focusSeconds: Int { focusMinutes * 60 }
    var breakSeconds: Int { breakMinutes * 60 }

    var focusMinutes: Int {
        switch self {
        case .classic: 25
        case .deep: 50
        case .quick: 15
        case .custom: 25
        }
    }

    var breakMinutes: Int {
        switch self {
        case .classic: 5
        case .deep: 10
        case .quick: 3
        case .custom: 5
        }
    }
}
