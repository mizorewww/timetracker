# Localization

Status: current localization contract

Supported languages: English (`en`), Simplified Chinese (`zh-Hans`), Traditional Chinese (`zh-Hant`).

User-facing copy goes into each target's `.lproj/Localizable.strings`. Use `AppStrings.localized(_:)` or a named `AppStrings` property from main-app Swift code. Display/extension metadata belongs in each target's `InfoPlist.strings`; App Shortcut phrase templates belong in the main app's `AppShortcuts.strings`.

## Rules

- Add every new key to all three languages in the same change. `make localization-check` and the pre-commit gate compare key sets across locales and resource families (`Localizable`, `InfoPlist`, `AppShortcuts`); they need no `xcodebuild`.
- Prefer concise labels that fit on iPhone.
- Avoid implementation terms in everyday UI; use ledger terminology only when the user edits historical records or reads data-management settings.
- Never expose legacy task workflow values (`planned`, `active`, `completed`) as product state. The task product vocabulary is Archive/Restore; deletion copy is reserved for reset, ledger/checklist entities, and historical tombstone fallbacks, never an ordinary task action. Checklist completion copy belongs to checklist items and does not imply the task is locked.
- Forecast copy states whether the source is the user's explicit estimate or checklist evidence. Recent-pace language may describe projected active days but must not imply history generated the remaining work amount.
- Duration, clock, and date text follow locale and the system 12/24-hour preference (`Services/Ledger/TimeFormatters.swift` uses `Duration.FormatStyle` / `Date.FormatStyle`); tests cover English and both Chinese locales instead of fixed `h/m`, `HH:mm`, or `MM/dd` output.
- App Intent titles/descriptions/parameters, shortcut short titles, and the task entity name use literal keys in all three main-app `Localizable.strings`; interpolated shortcut phrases are localized in each locale's `AppShortcuts.strings`. Verify Shortcuts/Siri discovery after changing them.
