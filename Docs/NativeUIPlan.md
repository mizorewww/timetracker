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
| Settings | `Form` in a settings window on macOS; keep Settings as a bottom-chrome destination on iPhone |
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
- iPhone settings remain a first-class bottom-chrome destination, not a Today toolbar sheet.
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

## 2026-05-17 Native Migration Execution Plan

This section is the detailed continuation plan for the SwiftUI modernization branch. When work resumes after context compaction, continue from this table and update the matching checklist in `Docs/SwiftUIModernizationChecklist-2026-05-17.md`.

### Decision Rules

- Prefer native controls for settings, forms, action rows, empty states, finite selections, text entry, navigation, and row actions.
- Keep custom drawing only when it represents product-specific data visualization or interaction that native controls do not cover cleanly: Pomodoro timer face, iPhone bottom chrome, analytics timelines, activity distribution bars, and compact task visual badges.
- Keep iPhone bottom chrome as a product-specific custom navigation surface. The product roadmap expects more than five destinations, so the paged bottom selector is the scalability path; do not replace it with a fixed five-item `TabView`, and do not move Settings into Today just to reduce the destination count.
- Every migration must keep or improve accessibility labels, Dynamic Type behavior, keyboard support, VoiceOver actions, and Reduce Motion behavior.
- Every migration must be independently revertible: one small behavior-preserving change, one focused test/update, then one commit.
- Source-string tests may be used as temporary guardrails, but new behavior should prefer state, command, accessibility, or UI tests when practical.

### Apple Documentation Anchors

- SwiftUI `Form`: settings and inspectors should use platform-appropriate form styling.
- SwiftUI `LabeledContent`: value-bearing controls in forms should align labels and controls consistently.
- SwiftUI `Picker`: finite choices should use native picker controls instead of hand-built popovers or button lists.
- SwiftUI `MenuPickerStyle.menu`: use menu style when there are more than five options.
- SwiftUI `ContentUnavailableView`: empty, unavailable, and error states should use the system empty-state presentation.
- SwiftUI `Button`, `Menu`, `contextMenu`, and `swipeActions`: row actions should use native action surfaces instead of gesture-only rows.
- SwiftUI `TabView`: use as the baseline native comparison for top-level tabs before choosing custom phone navigation.
- HIG Tab bars: system tab bars can reveal overflow with a More tab or convert to sidebar patterns in more complex iPadOS layouts; if the app ever abandons its product-specific bottom chrome, re-evaluate those native options before designing another custom replacement.

### Migration Matrix

| Area | Current Pattern | Native Target | Keep Custom? | Verification |
| --- | --- | --- | --- | --- |
| Settings empty rows | Hand-built icon/text `HStack` rows | Shared `SettingsUnavailableRow` backed by `ContentUnavailableView` | No | Source contract plus visual smoke in Settings |
| Pomodoro minute values | Button opens custom popover/wheel/list | `Picker` with `.menu` in `Form` | No | Contract test rejects `.popover` and wheel/list helper |
| Settings action rows | Shared row label with chevron | Keep only while it wraps native `Button`; consider `Label`-based row helper next | Temporary | Shared component contract and VoiceOver labels |
| LLM model loading row | Custom status row with `ProgressView` | Keep compact progress row; consider native `Picker` once models exist | Temporary | Existing LLM source contract |
| Countdown event editing | Native `TextField`, `DatePicker`, delete button | Keep native controls; replace empty row only | No for empty row | Settings contract and compile |
| Task detail editor | Card-style editor using native fields | Future: move full editing into `Form` sheet on macOS/iOS where possible | Product-dependent | Task detail UI contract and iOS build |
| Inbox suggestion row | Custom compact action surface | Keep for width-sensitive apply/discard workflow; ensure buttons are native | Yes, for compact layout | Existing Inbox UI contract and smallest-width screenshot |
| Today cards | Repeated custom cards | Use `List`/`Section` where possible; keep metric cards only when they present dense dashboard data | Partial | Home UI contract plus screenshots |
| Analytics charts | Swift Charts plus custom timeline/bar drawing | Keep custom drawing where chart semantics require it; use native empty states and legends | Yes | Analytics service tests and UI smoke |
| Phone bottom chrome | Custom paged bottom destination selector | Keep as product-specific navigation chrome; Settings stays in the destination list; improve pagination, accessibility identifiers, Reduce Motion, and hit targets instead of replacing with a fixed `TabView` | Yes | Phone chrome source-layout tests, source-contract tests, iOS build, and UI smoke |

### Bottom Chrome Rationale

The iPhone bottom chrome is intentionally custom. It already behaves as a paged selector, which is the right shape for a roadmap with many pages. A fixed native `TabView` would force an early information-architecture cap in this app and would likely require moving important destinations, such as Settings, into unrelated screens. That would make future expansion harder and would make Settings less discoverable.

Settings stays in the bottom model because it is a primary app surface, it needs to remain predictable across phone sessions, and hiding it under Today would couple unrelated destinations. The user has also explicitly chosen this product direction: do not move Settings during the modernization pass.

Refactor rule: keep the custom bottom chrome, keep Settings as a bottom destination, and improve the component itself. Preferred improvements are stable accessibility identifiers for every destination, clearer page indicators, stronger Reduce Motion behavior, preloading or caching destination state where profiling proves benefit, and tighter source-layout boundaries. Do not move Settings to Today unless the product navigation model changes explicitly. If the roadmap later chooses native-only navigation, evaluate `TabView` overflow behavior, `TabSection`, and iPad sidebar conversion as a separate information-architecture change rather than a drive-by refactor.

### Execution Order

1. Settings native pass:
   - Replace empty Pomodoro/Countdown rows with `ContentUnavailableView`.
   - Replace Pomodoro minute popover/list with native `Picker(.menu)`.
   - Keep `Form`, `Section`, `Toggle`, `TextField`, `SecureField`, `DatePicker`, and `Picker` as the baseline settings language.
   - Verify macOS target tests and generic iOS build.
2. Source-contract reconciliation:
   - Update stale Analytics, Inbox, and Phone source-string tests so they read split files and assert intended behavior, not obsolete file-local strings.
   - Keep failing behavior test `TaskCategoryTests.taskTreeShowsEmptyCategories` separate from UI source-contract cleanup.
3. HIG visual pass:
   - Review Settings, Today, Tasks, Inbox, Analytics, Pomodoro in light and dark modes.
   - Record screenshot or manual acceptance notes for macOS and compact iPhone.
   - Fix only concrete issues: forced dark surfaces, clipped text, competing primary actions, insufficient tap targets, or duplicated custom controls.
4. Performance evidence pass:
   - Build Release.
   - Run Instruments SwiftUI profiling on Today, Tasks search, Task Detail, Analytics, Settings, and Pomodoro.
   - Only optimize code paths confirmed by Instruments or existing performance tests.
5. Architecture pass:
   - Move facade logic into domain stores/services only when touching the feature.
   - Evaluate Observation migration as a dedicated branch-sized change, not as incidental cleanup.

## Manual Screenshot Checklist

For each future UI polish round, capture or manually inspect:

- iPhone Inbox with no items, one suggestion, many items, and dismissed suggestion.
- iPhone Today with no active timers, one timer, multiple timers.
- iPhone Tasks with nested tasks and long titles.
- iPad landscape with sidebar visible, collapsed, and inspector visible.
- macOS settings window and main split view.
- Analytics Today with short tasks, overlapping tasks, and empty data.
