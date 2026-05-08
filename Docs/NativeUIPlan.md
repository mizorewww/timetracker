# Native UI Plan

This document defines how future UI work should move toward native Apple components and away from fragile custom drawing. It should be checked before redesigning or adding any screen.

## Goal

The app should feel like a first-party Apple productivity app:

- calm hierarchy
- native navigation
- predictable controls
- system gestures
- readable compact layouts
- minimal custom animation
- no layout surprises when text, device width, or localization changes

Custom drawing is allowed only when the product concept requires it, such as analytics timelines or activity distribution charts. Editors, lists, settings, menus, sheets, and navigation should be native-first.

## Native-First Rules

Use these before building a custom view:

| Need | Prefer |
| --- | --- |
| Screen navigation | `NavigationStack`, `NavigationSplitView`, `TabView`, `.inspector` |
| Dense item list | `List`, `Section`, `ForEach`, `swipeActions`, `contextMenu` |
| Editing structured data | `Form`, `LabeledContent`, `Picker`, `Toggle`, `TextField`, `DatePicker`, toolbar cancel/save |
| Settings | `Form` in a settings window on macOS, pushed page or sheet on iOS |
| Choice from finite options | `Picker` with menu/inline/segmented style depending on space |
| Context actions | `Menu`, `contextMenu`, native toolbar items |
| Primary/secondary actions | `Button` with `.borderedProminent`, `.bordered`, `.plain` only for icon-only affordances |
| Progress | `ProgressView`, native gauges where possible |
| Search | `.searchable` |
| Disclosure | `DisclosureGroup` only for simple content, not recursive task trees |
| Reorder | `List` `onMove` or platform-native edit mode |

Avoid:

- Manually drawing controls that duplicate system buttons.
- Invisible text inside compact buttons.
- `ScrollView` containing a fixed-height `List` unless a design note explains why.
- Custom sidebar toggles when the split view already provides one.
- Animation on scroll title size changes, row identity changes, or list height changes.
- Cards inside cards.
- Using color alone to convey meaning.

## Screen Plans

### Inbox

Current risk: the screen uses custom card layout plus an embedded `List`, and the suggestion row is sensitive to width.

Plan:

- Keep native list behaviors for rows: swipe, context menu, edit/reorder.
- Split the screen into small components before more visual work.
- Consider replacing the custom card with `List` sections on iPhone if the current card continues to fight native scrolling.
- Suggestion row should stay compact:
  - label: `Suggest`
  - content: task name only
  - actions: discard and apply
  - no path
  - no icon unless there is enough width
- Capture row should behave like a native text field: submit clears and refocuses.

Acceptance:

- No horizontal clipping on the smallest iPhone width.
- Swipe actions remain visible after suggestion dismissal.
- The large top plus and inline plus do not compete visually.

### Today

Current risk: Today contains many concepts: metrics, active timers, forecast, timeline, quick start, and settings entry.

Plan:

- Use native large title on iPhone.
- Keep metric height low and avoid decorative charts when the data is not useful.
- Use system buttons for Start Timer and New Task.
- On iPhone, active timer rows can split into two lines:
  - line 1: icon, title, parent path
  - line 2: duration and actions
- Quick Start should be editable through a native sheet/list, not custom chips when editing.

Acceptance:

- Today does not jitter when scrolling from bottom to top.
- Active timer controls remain tappable at 44 pt minimum.
- Metrics do not dominate the first screen.

### Tasks

Current risk: task rows are information-dense, especially on iPhone.

Plan:

- Keep `List` with flat visible rows from `TaskTreeFlattener`.
- Use native swipe actions for start, child task, edit, and delete.
- Put task status in a secondary line on compact width.
- Put checklist progress on the trailing side only when there is enough width; otherwise show it below the title line.
- Category headers should be native section headers with subtle dividers, not custom drop targets.
- Reordering and moving should use reliable native edit/menu flows before drag-and-drop is reintroduced.

Acceptance:

- Every visible task is an independent row for tap, context menu, and swipe actions.
- Indentation is stable across expand/collapse.
- Deleting or creating a task preserves the Tasks destination.

### Task Editor

Current risk: checklist editing and visual editing can become custom and inconsistent.

Plan:

- Keep editor as `NavigationStack` + `Form`.
- Use `LabeledContent`, native `Picker`, `TextField`, `Toggle`, and toolbar save/cancel.
- Reuse `SymbolColorPickerRow` for tasks, categories, checklist items, and Inbox suggestion visuals.
- Checklist rows should reuse one shared row component where possible.
- macOS can use up/down controls for checklist ordering; iOS can use native move.

Acceptance:

- Long checklist text wraps.
- Return submits where the user expects submit, not newline, unless the field explicitly supports notes.
- Adding checklist item creates a focused empty row.

### Analytics

Current risk: analytics charts require custom drawing, but surrounding UI should still be native.

Plan:

- Keep chart math in services and render `AnalyticsSnapshot`.
- Wrap chart sections in native section-like containers with consistent headers.
- Use Swift Charts where it fits; use custom drawing only for timeline and stacked activity where Swift Charts is not expressive enough.
- Legends should be native rows with swatches and labels.
- Today distribution should show task colors and not collapse short tasks into one-pixel lines.

Acceptance:

- Today, Week, and Month share data semantics.
- Empty states explain what data is missing.
- Long task names do not overlap charts.

### Settings

Current risk: settings can drift into debug panels.

Plan:

- macOS settings should open as a settings window.
- iOS settings can be a sheet or pushed page.
- Use native `Form`, grouped sections, `Toggle`, `Picker`, `TextField`, and `Button`.
- Keep debug/status-only information under About or Advanced.
- User settings should explain the outcome, not implementation details.

Acceptance:

- iCloud settings are understandable to non-developers.
- API key/model settings are clearly marked and secure.
- Destructive maintenance actions have confirmation text.

### Sidebar And Inspector

Current risk: split view controls have been fragile on iPad.

Plan:

- Let `NavigationSplitView` own sidebar visibility when possible.
- Do not duplicate the system sidebar toggle.
- Inspector appears only when the current destination has meaningful selected-task detail.
- Sidebar task rows should be simple navigation rows, not mini task editors.

Acceptance:

- Collapsing the sidebar always leaves a native way to reopen it.
- Sidebar and inspector can be controlled independently.
- Selecting a task makes the detail destination clear to the user.

## Component Inventory

Keep and refine:

- `TaskVisuals`
- `ChecklistControls`
- `SettingsRows`
- `StatusBadges`
- `MetricCards`
- `SectionHeaders`
- `TaskProgressViews`
- `LayoutPolicies`

Review before further reuse:

- `ActionControls`: make sure it wraps native button styles rather than inventing new ones.
- `DesignSystem.cardStyle`: limit use to repeated content or framed data.
- `MetricCards`: avoid turning every statistic into a card.

Avoid adding:

- New custom button styles for one screen.
- New custom segmented controls.
- Custom modal chrome.
- Custom sidebar toggles.
- Custom row swipe gestures.

## Native UI Review Checklist

Before merging UI work:

1. Is there a native component that already does this?
2. Does it work on the smallest iPhone width?
3. Does it work in iPad split view with sidebar and inspector states?
4. Does it work in macOS narrow and full-screen windows?
5. Does long localized text wrap or truncate intentionally?
6. Are all tappable targets at least 44 pt on touch platforms?
7. Are row identities stable during scrolling and animation?
8. Is custom animation necessary, or can the system interaction speak for itself?
9. Are visual-only changes covered by a manual screenshot checklist rather than brittle source-string tests?
10. Are user-facing strings localized in all three languages?

## Manual Screenshot Checklist

For each future UI polish round, capture or manually inspect:

- iPhone Inbox with no items, one suggestion, many items, and dismissed suggestion.
- iPhone Today with no active timers, one timer, multiple timers.
- iPhone Tasks with nested tasks and long titles.
- iPad landscape with sidebar visible, collapsed, and inspector visible.
- macOS settings window and main split view.
- Analytics Today with short tasks, overlapping tasks, and empty data.
