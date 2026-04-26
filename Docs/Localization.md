# Localization

Supported languages:

- English (`en`)
- Simplified Chinese (`zh-Hans`)
- Traditional Chinese (`zh-Hant`)

User-facing copy should be added to the `Localizable.strings` files under each `.lproj` folder. Use `AppStrings.localized(_:)` or a named `AppStrings` property for strings used from Swift code.

## Rules

- Do not hard-code user-facing Chinese text in Swift source. The unit test `swiftSourcesDoNotContainHardCodedChineseText` enforces this.
- Do not add a new localized key to only one language. The unit test `localizationFilesExposeTheSameKeys` requires all locale files to expose the same keys.
- Prefer concise labels that fit on iPhone.
- Avoid implementation terms in everyday UI. Use ledger terminology only when the user is editing historical records or reading data-management settings.
- When adding a key, add it to all three languages in the same change.

## Current Migration State

The refactor branch localizes navigation, Today, Tasks, Pomodoro, Analytics, Settings, task editing, segment editing, manual time entry, Live Activity fallbacks, sync status, and core validation errors.

Demo data is seeded with ASCII titles and notes so it does not bypass localization tests. Future demo content that must be localized should be produced through localized string keys at seed time.
