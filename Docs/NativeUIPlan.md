# Native UI Plan

Status: future UI guardrails and manual acceptance checklist. Current user behavior is documented in [UserGuide](UserGuide.md); completed redesign history is documented in [Audit-2026-07-14](Audit-2026-07-14.md).

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
- Keeping a dense horizontal row at Accessibility Dynamic Type sizes when a vertical composition or native menu can preserve the full title, value, and action.

## Screen Plans

### Inbox

Current state: the screen uses one native `List`; the earlier custom card plus embedded-list shell was removed. Remaining work is behavioral and device acceptance, not another container rewrite.

Plan:

- Keep native list behaviors for rows: swipe, context menu, edit/reorder.
- Split the screen into small components before more visual work.
- Keep capture, open items, completed items and suggestion feedback in native list sections.
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
- Capture and navigation actions do not compete visually.

### Today

Current state: iPhone Today is a native priority-ordered `List` with active timers, summary, Quick Start, forecast, timeline and optional countdown. Generic day/week/month/year progress and selected-task cards were removed.

Plan:

- Use native large title on iPhone.
- Keep gross/wall summary compact and avoid adding decorative progress or duplicate metrics.
- Use system buttons for Start Timer and New Task.
- On iPhone, active timer rows can split into two lines:
  - line 1: icon, title, parent path
  - line 2: duration and actions
- Quick Start should be editable through a native sheet/list, not custom chips when editing.

Acceptance:

- Today does not jitter when scrolling from bottom to top.
- Active timer controls remain tappable at 44 pt minimum.
- Metrics do not dominate the first screen.
- Accessibility Extra Large keeps task titles, paths, durations, stop actions, Quick Start labels, countdown dates, and the final list rows visible without overlap or tab-bar obstruction.

### Tasks

Current risk: task rows are information-dense, especially on iPhone.

Plan:

- Keep `List` with flat visible rows from `TaskTreeFlattener`.
- Use native swipe actions for start, child task, edit, and delete.
- Put task status in a secondary line on compact width.
- Put checklist progress on the trailing side only when there is enough width; otherwise show it below the title line.
- Category headers should be native section headers with subtle dividers, not custom drop targets.
- Reordering and moving should use reliable native edit/menu flows before drag-and-drop is reintroduced.
- Keep completed tasks as visible native rows with an explicit unavailable-work explanation and reopen action. Archived branches stay hidden; do not make both states look like deletion.

Acceptance:

- Every visible task is an independent row for tap, context menu, and swipe actions.
- Indentation is stable across expand/collapse.
- Deleting or creating a task preserves the Tasks destination.
- A completed parent and its children remain navigable, cannot start new work, and expose a clear path-level reopen action without losing history.

### Task Editor

Current risk: checklist editing and visual editing can become custom and inconsistent.

Plan:

- Keep editor as `NavigationStack` + `Form`.
- Use `LabeledContent`, native `Picker`, `TextField`, `Toggle`, and toolbar save/cancel.
- Keep the task estimate control explicit: 15-minute steps, zero as “not set,” and a concise explanation that it estimates this task's own work while child forecasts remain separate.
- Reuse `SymbolColorPickerRow` for tasks, categories, checklist items, and Inbox suggestion visuals.
- Checklist rows should reuse one shared row component where possible.
- macOS can use up/down controls for checklist ordering; iOS can use native move.

Acceptance:

- Long checklist text wraps.
- Return submits where the user expects submit, not newline, unless the field explicitly supports notes.
- Adding checklist item creates a focused empty row.
- Forecast source copy distinguishes an explicit task estimate from checklist evidence and remains readable at accessibility sizes.

### Analytics

Current state: the landing page uses typed category navigation and the category destination has a focused owner. Analytics charts still require some custom drawing, but surrounding UI should remain native.

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
- The landing page keeps a small summary plus category navigation; at accessibility sizes the range picker may become a menu instead of forcing a segmented control to clip.

### Pomodoro

Current state: setup uses explicit Plan and Task menus. Its composition, empty state, focus controls, selection controls, and timer face have separate owners; active-run and ledger presentation remain separate sections.

Plan:

- Keep Plan and Task as labeled, discoverable controls; do not restore title/timer-face tap gestures as hidden selection shortcuts.
- Prefer native menus, buttons, progress, and text over custom hit testing. Keep every primary touch action at least 44 pt.
- Let setup controls reflow under Dynamic Type instead of shrinking the timer or truncating task identity.
- Keep the timer face presentational: durable phase, deadline, and ledger changes belong to the store/commands.

Acceptance:

- Empty state explains why focus cannot start and exposes the next valid action.
- Long localized Plan/Task names remain readable at Accessibility Extra Large.
- VoiceOver announces selected plan, selected task, phase, remaining time, and the primary action without relying on color or shape alone.
- Background/foreground reconciliation does not create a new focus segment without an explicit user action.

### Settings

Current state: settings uses category navigation for General, Focus, Data & Sync, AI Assistant and Advanced. The app follows system appearance. Shared foundation/value, action/destructive, input, platform-presentation, and sync-feedback rows have separate owners.

Plan:

- macOS settings should open as a settings window.
- iOS settings can be a sheet or pushed page.
- Use native `Form`, grouped sections, `Toggle`, `Picker`, `TextField`, and `Button`.
- Reflow value and input rows vertically at accessibility Dynamic Type sizes; expose one clear VoiceOver label/value instead of reading decorative icons.
- Pair destructive button roles with explicit text, red title/icon treatment, and confirmation copy; color alone is never the warning contract.
- Keep debug/status-only information under About or Advanced.
- User settings should explain the outcome, not implementation details.

Acceptance:

- iCloud settings are understandable to non-developers.
- API key/model settings are clearly marked and secure.
- Destructive maintenance actions have confirmation text.
- Long localized labels and values remain readable at Accessibility Extra Large, and sync feedback announces both state and explanation.

### Sidebar And Detail

Current state: iPad and macOS use `NavigationSplitView`; selecting a sidebar task opens the canonical read-first Task Detail. There is no separate Inspector feature.

Plan:

- Let `NavigationSplitView` own sidebar visibility when possible.
- Do not duplicate the system sidebar toggle.
- Keep task detail as the single canonical selected-task surface; do not add a second inspector that diverges from it without a product need.
- Sidebar task rows should be simple navigation rows, not mini task editors.

Acceptance:

- Collapsing the sidebar always leaves a native way to reopen it.
- Collapsing and restoring the sidebar preserves the current detail.
- Selecting a task makes the detail destination clear to the user.

## Component Inventory

Keep and refine:

- `TaskVisuals`
- `ChecklistControls`
- `SettingsRows`, `SettingsActionRows`, `SettingsInputRows`, `SettingsPresentationModifiers`, `SettingsSyncFeedbackRow`
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
3. Does it work in iPad split view with sidebar visible and collapsed?
4. Does it work in macOS narrow and full-screen windows?
5. Does long localized text wrap or truncate intentionally?
6. Are all tappable targets at least 44 pt on touch platforms?
7. Are row identities stable during scrolling and animation?
8. Is custom animation necessary, or can the system interaction speak for itself?
9. Are visual-only changes covered by a manual screenshot checklist rather than brittle source-string tests?
10. Are user-facing strings localized in all three languages?
11. At normal text sizes, are the main hierarchy and ordinary interaction path clear and unobscured? If this change affects text reflow/truncation, also run the targeted large-text check for the affected rows.

## Manual Screenshot Checklist

For each future UI polish round, capture or manually inspect the affected normal-text-size flows below. Do not rerun every screen or maximum Dynamic Type by default; add dark appearance, long localization, or large-text cases only when the changed layout or a reported regression makes them relevant:

- iPhone Inbox with no items, one suggestion, many items, and dismissed suggestion.
- iPhone Today with no active timers, one timer, multiple timers.
- iPhone Tasks with nested tasks and long titles.
- iPhone Tasks and Task Detail with a completed parent, blocked child, and reopened path.
- iPhone dark appearance, long localization, or large text for only the screens whose layout changed.
- iPad landscape Today and Task Detail with the sidebar visible and collapsed.
- macOS settings window and main split view.
- Analytics Today with short tasks, overlapping tasks, and empty data.
