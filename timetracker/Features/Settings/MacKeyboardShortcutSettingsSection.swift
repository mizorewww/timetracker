#if os(macOS)
import MacKeyboardShortcuts
import SwiftUI

struct MacKeyboardShortcutSettingsSection: View {
    let settings: MacKeyboardShortcutSettings

    var body: some View {
        Group {
            ForEach(MacKeyboardShortcutGroup.allCases) { group in
                Section {
                    ForEach(group.actions) { action in
                        shortcutRecorder(for: action)
                    }
                } header: {
                    groupHeader(for: group)
                } footer: {
                    if group == .data {
                        Text(.app("settings.keyboardShortcuts.footer"))
                    }
                }
            }
        }
        .keyboardShortcutsConflictPolicy(
            .init(
                menuItem: .block,
                systemShortcut: .block,
                disallowed: .block
            )
        )

        Section {
            Button(AppStrings.localized("settings.keyboardShortcuts.resetAll")) {
                settings.resetAll()
            }
            .disabled(settings.isUsingDefaults)
            .accessibilityIdentifier("settings.shortcuts.resetAll")
        }
    }

    @ViewBuilder
    private func groupHeader(
        for group: MacKeyboardShortcutGroup
    ) -> some View {
        if group == .creation {
            VStack(alignment: .leading, spacing: 8) {
                SettingsHeader(
                    symbol: "keyboard",
                    title: AppStrings.localized(
                        "settings.keyboardShortcuts.title"
                    )
                )
                .accessibilityIdentifier("settings.shortcuts.view")
                Text(group.title)
            }
        } else {
            Text(group.title)
        }
    }

    private func shortcutRecorder(
        for action: MacKeyboardShortcutAction
    ) -> some View {
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
