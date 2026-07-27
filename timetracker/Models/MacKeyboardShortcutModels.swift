#if os(macOS)
import AppKit
import MacKeyboardShortcuts

enum MacKeyboardShortcutAction:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case addTime
    case startSelectedTask
    case startPomodoro
    case refreshData

    var id: Self {
        self
    }

    var defaultShortcut: KeyboardShortcuts.Shortcut {
        switch self {
        case .addTime:
            KeyboardShortcuts.Shortcut(.m, modifiers: [.command, .shift])
        case .startSelectedTask:
            KeyboardShortcuts.Shortcut(.s, modifiers: [.command, .shift])
        case .startPomodoro:
            KeyboardShortcuts.Shortcut(.p, modifiers: [.command, .shift])
        case .refreshData:
            KeyboardShortcuts.Shortcut(.r, modifiers: [.command])
        }
    }

    static let reservedShortcuts: Set<KeyboardShortcuts.Shortcut> = [
        KeyboardShortcuts.Shortcut(.n, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.comma, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.one, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.two, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.three, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.four, modifiers: [.command]),
        KeyboardShortcuts.Shortcut(.five, modifiers: [.command]),
    ]

    static let standaloneFunctionKeys: Set<KeyboardShortcuts.Key> = [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
        .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
    ]
}

enum MacKeyboardShortcutStoredOverride: Codable, Equatable {
    case disabled
    case custom(KeyboardShortcuts.Shortcut)
}

struct MacKeyboardShortcutPayload: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var overrides: [String: MacKeyboardShortcutStoredOverride] = [:]

    func resolvedOverrides() -> [MacKeyboardShortcutAction:
        MacKeyboardShortcutStoredOverride]?
    {
        guard schemaVersion == Self.currentSchemaVersion else {
            return nil
        }

        var resolved: [MacKeyboardShortcutAction:
            MacKeyboardShortcutStoredOverride] = [:]
        for (rawAction, override) in overrides {
            guard let action = MacKeyboardShortcutAction(rawValue: rawAction) else {
                continue
            }
            if case let .custom(shortcut) = override,
               shortcut.toSwiftUI == nil
            {
                return nil
            }
            resolved[action] = override
        }
        return resolved
    }
}

enum MacKeyboardShortcutValidationError: Error, Equatable {
    case duplicate(MacKeyboardShortcutAction)
    case reserved
    case unsupported
}
#endif
