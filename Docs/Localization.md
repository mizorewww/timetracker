# Localization

Status: current localization contract

Reviewed: 2026-07-15

Supported languages:

- English (`en`)
- Simplified Chinese (`zh-Hans`)
- Traditional Chinese (`zh-Hant`)

User-facing copy should be added to the `Localizable.strings` files under each target's `.lproj` folders. Use `AppStrings.localized(_:)` or a named `AppStrings` property for strings used from main-app Swift code. App display/extension metadata belongs in each target's `InfoPlist.strings`; App Shortcut phrase templates belong in the main app's `AppShortcuts.strings`.

## Rules

- Do not hard-code user-facing Chinese text in Swift source. The unit test `swiftSourcesDoNotContainHardCodedChineseText` enforces this.
- Do not add a new localized key to only one language. The unit test `localizationFilesExposeTheSameKeys` requires all locale files to expose the same keys.
- Keep `InfoPlist.strings` in parity for the main app, Live Activity, Widget, and Watch, and keep the main app's `AppShortcuts.strings` in parity. These resource families currently need an explicit plist/static check in addition to the `Localizable.strings` unit suite.
- Prefer concise labels that fit on iPhone.
- Avoid implementation terms in everyday UI. Use ledger terminology only when the user is editing historical records or reading data-management settings.
- When adding a key, add it to all three languages in the same change.

## Current Migration State

The current worktree localizes navigation, Today, Tasks, Pomodoro, Analytics, Settings, task editing, segment editing, manual time entry, Live Activity fallbacks, sync status, and core validation errors.

Demo data is seeded with ASCII titles and notes so it does not bypass localization tests. Future demo content that must be localized should be produced through localized string keys at seed time.

App Intent titles, descriptions, parameters, shortcut short titles, and the task entity name use literal-key entries in all three main-app `Localizable.strings` files. The six interpolated shortcut phrase templates are localized separately in each locale's `AppShortcuts.strings`; keep those resources in parity and verify Shortcuts/Siri discovery after changing them because ordinary `Localizable.strings` key-parity checks do not cover this resource.

`KeychainCredentialError` resolves invalid-data, unknown-failure, and operation-failure copy from the three main localization files. The formatted operation error keeps the OSStatus and system-provided diagnostic message while avoiding hard-coded English in the user-facing fallback.

`Services/Ledger/TimeFormatters.swift` uses locale-aware `Duration.FormatStyle` for compact durations and `Date.FormatStyle` for clock/date presentation. `TimeTrackerUtilityTests` covers English and both Chinese duration output plus US/British time conventions and Chinese date ordering. Stopwatch-style elapsed clocks remain colon-delimited numeric durations rather than wall-clock dates.
