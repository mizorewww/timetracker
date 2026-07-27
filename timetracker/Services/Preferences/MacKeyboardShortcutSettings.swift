#if os(macOS)
import MacKeyboardShortcuts
import Observation

@MainActor
@Observable
final class MacKeyboardShortcutSettings {
    private struct Value: Equatable {
        var shortcut: KeyboardShortcuts.Shortcut?
    }

    private let command: MacKeyboardShortcutPreferenceCommand
    private var values: [MacKeyboardShortcutAction: Value]
    private(set) var revision = 0

    init(command: MacKeyboardShortcutPreferenceCommand? = nil) {
        let command = command ?? MacKeyboardShortcutPreferenceCommand()
        self.command = command
        values = Dictionary(
            uniqueKeysWithValues: MacKeyboardShortcutAction.allCases.map {
                ($0, Value(shortcut: command.shortcut(for: $0)))
            }
        )
    }

    func shortcut(
        for action: MacKeyboardShortcutAction
    ) -> KeyboardShortcuts.Shortcut? {
        values[action]?.shortcut
    }

    @discardableResult
    func setShortcut(
        _ shortcut: KeyboardShortcuts.Shortcut?,
        for action: MacKeyboardShortcutAction
    ) -> Bool {
        do {
            try command.setShortcut(shortcut, for: action)
            values[action] = Value(shortcut: shortcut)
            revision += 1
            return true
        } catch {
            return false
        }
    }

    func resetAll() {
        command.resetAll()
        values = Dictionary(
            uniqueKeysWithValues: MacKeyboardShortcutAction.allCases.map {
                ($0, Value(shortcut: $0.defaultShortcut))
            }
        )
        revision += 1
    }

    func conflictingAction(
        for shortcut: KeyboardShortcuts.Shortcut,
        excluding action: MacKeyboardShortcutAction
    ) -> MacKeyboardShortcutAction? {
        MacKeyboardShortcutAction.allCases.first {
            $0 != action && values[$0]?.shortcut == shortcut
        }
    }
}
#endif
