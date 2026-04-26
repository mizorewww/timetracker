# Localization

Supported languages:

- English (`en`)
- Simplified Chinese (`zh-Hans`)
- Traditional Chinese (`zh-Hant`)

User-facing copy should be added to the `Localizable.strings` files under each `.lproj` folder. Use `AppStrings.localized(_:)` or a named `AppStrings` property for strings used from Swift code.

## Rules

- Do not hard-code new user-facing strings in views unless they are temporary during active development.
- Prefer concise labels that fit on iPhone.
- Avoid implementation terms in everyday UI. Use ledger terminology only when the user is editing historical records or reading data-management settings.
- When adding a key, add it to all three languages in the same change.

## Current Migration State

The first refactor pass localizes the main navigation, Today surface, primary actions, key menus, and app display name. Older strings in deep forms still need to be migrated gradually.
