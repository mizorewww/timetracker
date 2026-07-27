#if os(macOS)
import MacKeyboardShortcuts
import SwiftUI

struct MacKeyboardShortcutSettingsSection: View {
    let settings: MacKeyboardShortcutSettings

    var body: some View {
        Section {
            ForEach(MacKeyboardShortcutAction.allCases) { action in
                LabeledContent {
                    KeyboardShortcuts.Recorder(
                        shortcut: binding(for: action)
                    )
                    .shortcutValidation { shortcut in
                        validationResult(for: shortcut, action: action)
                    }
                } label: {
                    Text(action.title)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(
                    "settings.shortcuts.recorder.\(action.rawValue)"
                )
            }
        } header: {
            SettingsHeader(
                symbol: "keyboard",
                title: AppStrings.localized("settings.keyboardShortcuts.title")
            )
        } footer: {
            Text(.app("settings.keyboardShortcuts.footer"))
        }
        .keyboardShortcutsConflictPolicy(
            .init(
                menuItem: .block,
                systemShortcut: .block,
                disallowed: .block
            )
        )
        .accessibilityIdentifier("settings.shortcuts.view")

        Section {
            Button(AppStrings.localized("settings.keyboardShortcuts.resetAll")) {
                settings.resetAll()
            }
            .disabled(settings.isUsingDefaults)
            .accessibilityIdentifier("settings.shortcuts.resetAll")
        }
    }

    private func binding(
        for action: MacKeyboardShortcutAction
    ) -> Binding<KeyboardShortcuts.Shortcut?> {
        Binding {
            settings.shortcut(for: action)
        } set: { shortcut in
            settings.setShortcut(shortcut, for: action)
        }
    }

    private func validationResult(
        for shortcut: KeyboardShortcuts.Shortcut,
        action: MacKeyboardShortcutAction
    ) -> KeyboardShortcuts.ValidationResult {
        guard let conflict = settings.conflictingAction(
            for: shortcut,
            excluding: action
        ) else {
            return .allow
        }
        return .disallow(
            reason: String(
                format: AppStrings.localized(
                    "settings.keyboardShortcuts.duplicateFormat"
                ),
                conflict.title
            )
        )
    }
}
#endif
