#if os(macOS)
import MacKeyboardShortcuts

@MainActor
struct MacKeyboardShortcutPreferenceCommand {
    private let store: any MacKeyboardShortcutPreferenceStoring

    init(
        store: (any MacKeyboardShortcutPreferenceStoring)? = nil
    ) {
        self.store =
            store ?? UserDefaultsMacKeyboardShortcutPreferenceStore()
    }

    func shortcut(
        for action: MacKeyboardShortcutAction
    ) -> KeyboardShortcuts.Shortcut? {
        store.shortcut(for: action)
    }

    func setShortcut(
        _ shortcut: KeyboardShortcuts.Shortcut?,
        for action: MacKeyboardShortcutAction
    ) throws {
        if let shortcut {
            guard
                shortcut.toSwiftUI != nil,
                !shortcut.modifiers.isEmpty ||
                shortcut.key.map(
                    MacKeyboardShortcutAction.standaloneFunctionKeys.contains
                ) == true
            else {
                throw MacKeyboardShortcutValidationError.unsupported
            }
            guard
                !MacKeyboardShortcutAction.reservedShortcuts.contains(shortcut),
                !shortcut.isTakenBySystem
            else {
                throw MacKeyboardShortcutValidationError.reserved
            }
            if let duplicate = conflictingAction(
                for: shortcut,
                excluding: action
            ) {
                throw MacKeyboardShortcutValidationError.duplicate(duplicate)
            }
        }
        try store.setStoredShortcut(shortcut, for: action)
    }

    func resetAll() {
        store.resetStoredShortcuts()
    }

    func conflictingAction(
        for shortcut: KeyboardShortcuts.Shortcut,
        excluding action: MacKeyboardShortcutAction
    ) -> MacKeyboardShortcutAction? {
        MacKeyboardShortcutAction.allCases.first {
            $0 != action && store.shortcut(for: $0) == shortcut
        }
    }
}
#endif
