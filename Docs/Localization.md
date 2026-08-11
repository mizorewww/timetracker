# Localization

Status: current localization contract

Reviewed: 2026-07-19

Supported languages:

- English (`en`)
- Simplified Chinese (`zh-Hans`)
- Traditional Chinese (`zh-Hant`)

User-facing copy should be added to the `Localizable.strings` files under each target's `.lproj` folders. Use `AppStrings.localized(_:)` or a named `AppStrings` property for strings used from main-app Swift code. App display/extension metadata belongs in each target's `InfoPlist.strings`; App Shortcut phrase templates belong in the main app's `AppShortcuts.strings`.

## Rules

- Do not add a new localized key to only one language. `make localization-check` and the pre-commit gate compare key sets across all three locales.
- Keep `Localizable.strings`, `InfoPlist.strings`, and the main app's `AppShortcuts.strings` in parity for every target/resource family. The same static gate covers them without running `xcodebuild`.
- Prefer concise labels that fit on iPhone.
- Avoid implementation terms in everyday UI. Use ledger terminology only when the user is editing historical records or reading data-management settings.
- Do not expose or translate legacy task workflow values (`planned`, `active`, `completed`) as product state. Checklist completion copy belongs to checklist items and does not imply that the task is locked. The current task product vocabulary is Archive/Restore; deletion copy is reserved for reset, ledger/checklist entities, and historical tombstone fallbacks, never an ordinary task action.
- Forecast copy must identify whether the source is the user's explicit estimate or checklist evidence. Recent-pace language may describe projected active days but must not imply that history generated the remaining work amount.
- When adding a key, add it to all three languages in the same change.

## Current Migration State

The current worktree localizes navigation, Today, Tasks, archive lifecycle copy, explicit-estimate forecast reasons, Pomodoro, Analytics, Settings, task editing, segment editing, manual time entry, Live Activity fallbacks, sync status, and core validation errors.

Demo data uses locale-neutral fixture copy. Future demo content that is intended as product copy should be produced through localized string keys at seed time.

App Intent titles, descriptions, parameters, shortcut short titles, and the task entity name use literal-key entries in all three main-app `Localizable.strings` files. The six interpolated shortcut phrase templates are localized separately in each locale's `AppShortcuts.strings`; keep those resources in parity and verify Shortcuts/Siri discovery after changing them.

`KeychainCredentialError` resolves invalid-data, unknown-failure, and operation-failure copy from the three main localization files. The formatted operation error keeps the OSStatus and system-provided diagnostic message while avoiding hard-coded English in the user-facing fallback.

`Services/Ledger/TimeFormatters.swift` uses locale-aware `Duration.FormatStyle` for compact durations and `Date.FormatStyle` for clock/date presentation. `TimeTrackerUtilityTests` covers English and both Chinese duration output plus US/British time conventions and Chinese date ordering. Stopwatch-style elapsed clocks remain colon-delimited numeric durations rather than wall-clock dates.
