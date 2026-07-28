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
            if let validationError =
                MacKeyboardShortcutAction.validationError(for: shortcut)
            {
                throw validationError
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
