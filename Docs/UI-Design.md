# UI Design Notes

Status: current UI guardrails

Reviewed: 2026-07-27

Current user behavior is documented in [User Guide](UserGuide.md); verification rules are maintained in [Testing](Testing.md). This document defines how UI work should move toward native Apple components and away from fragile custom drawing. Check it before redesigning or adding any screen.

The app should feel like a first-party Apple productivity tool: calm hierarchy, native navigation, predictable controls, system gestures, readable compact layouts, minimal custom animation, and no layout surprises when text, device width, or localization changes.

Layout adapts to **width, never to device model**. `AppRootView` measures the window and picks one of two shells — compact (tab bar) below 720 pt, regular (sidebar + detail) at or above it — and publishes the choice as `\.layoutShell` for nested views. An iPad in Split View and a Mac window dragged narrow therefore get the same layout an iPhone gets. Do not reintroduce `UIDevice.current.userInterfaceIdiom` or a `#if os(...)` branch to make a layout decision; `#if os(...)` is for APIs that only exist on one platform, and touch-target sizing stays platform-keyed because it encodes input modality (finger vs pointer), not width.

Custom drawing is allowed only when the product concept requires it, such as analytics timelines or activity distribution charts. Editors, lists, settings, menus, sheets, and navigation are native-first.

## Principles

- Prefer native `NavigationSplitView`, `NavigationStack`, `List`, `Form`, `Table`, sheets, popovers, menus, `Menu`, `Picker`, and toolbar items before custom controls.
- Do not add a custom primary-sidebar toggle to the iPad/macOS split view. Let `NavigationSplitView` provide the system sidebar affordance; custom `sidebar.left` buttons can duplicate the system control and disappear after collapsing.
- Cards are for repeated content or framed data, not for every section. Avoid cards inside cards.
- Today should answer three questions quickly: what is running, what happened today, and what can continue next.
- Forecast UI should explain where numbers come from. Forecast cards need an `info.circle` entry point, a short source label, and a plain-language reason. An explicit task estimate is a valid source without checklist evidence; otherwise do not show a numeric forecast until checklist progress and tracked time are sufficient. Recent pace may explain projected active days but must not imply it created the remaining work amount.
- Checklist UI belongs inside task editing and task detail surfaces. Do not present checklist items as timed subtasks; they are progress markers under a timed task.
- Checklist rows should behave like native to-do rows: a large circular check button, at least 44 pt row height, unfinished items first, completed items after them with strikethrough text. Adding a checklist item should create a focused empty row immediately. Checklist completion is the task's only product-level completion/progress signal and never disables later work.
- Do not show a task workflow-status picker, status badge, Complete action, Reopen action, or ordinary task Delete action. Legacy planned/active/completed raw values are invisible compatibility data and behave like ordinary tasks. Archived branches remain hidden and recover through Restore; historical tombstones remain a sync compatibility boundary, not a second UI lifecycle.
- iPhone layouts must split dense rows into two lines when icon, title, path, timer, and actions cannot fit.
- Task Detail is the one canonical deep surface on iPhone, iPad, and macOS. Do not add a second inspector that can drift from it unless a separately reviewed product need justifies the extra selection and synchronization state. For an ordinary task, its identity icon is an icon-only navigation affordance beside an editable title, not a full navigation row: keep the 44 pt icon target and 14 pt title gap, and hide the automatic navigation-link disclosure indicator so it does not create an accessory slot between icon and title.
- A canonical Apple Health task is the explicit read-only exception: its detail content contains only Summary, Task Analysis, and Recent Records, in that order. Day/Week/Month and historical-period controls belong at the top of Task Analysis instead of creating a fourth section. Do not show identity/editor, sync-only explanation, quantity, heatmap tracking, forecast, Add Time, More, Archive, autosave, or draft-recovery UI. Loading, empty, failure, unavailable, refresh, and retry feedback stays inside the analytics experience and must never fall back to ordinary-task content.
- Sheets should use system `NavigationStack` + `Form` + toolbar cancel/save actions. Avoid custom modal title bars unless the content is not an editor.
- Fixed sheet sizes are macOS-only. iPhone and iPad sheets must follow the platform presentation width so they do not overflow compact devices.
- The analytics timeline should separate graphic bars from task text. Bars show time, color, and icon; rows below carry labels.
- When a section shows every item, do not show inert "All" links. A disclosure or navigation affordance should only appear when it performs an action.
- Horizontal iPad/macOS Today action buttons should align to the metric panel height. If a metric card and action stack sit in the same row, their top and bottom edges should match.
- Expensive derived values are passed into rows, not recalculated by them.
- User-facing copy explains outcomes, not internal model names.
- Repeated cards, metric cells, chart containers, checklist controls, and layout breakpoints belong in `SharedUI` or layout policy types before a second feature copies them.

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

## Screen Notes

### Inbox

One native `List` with native row behaviors (swipe, context menu, edit/reorder); capture, open items, completed items, and suggestion feedback live in native list sections. The capture row behaves like a native text field: submit clears and refocuses. Acceptance: no horizontal clipping on the smallest iPhone width; swipe actions remain visible after suggestion dismissal; capture and navigation actions do not compete visually.

### Today

iPhone Today is a native priority-ordered `List` (Now, Overview, Weekly Gross Time, Activity Heatmaps, Quick Start, Timeline, Forecast, Countdown). Use the native large title, keep the gross/wall summary compact without decorative progress or duplicate metrics, and use system buttons for Start Timer and New Task. Quick Start edits through a native sheet/list, not custom chips.

Today section hierarchy has one owner. Overview, Weekly Gross Time, and Activity Heatmaps use `HomeSectionHeader`: card layouts render the title with system `.headline`; iPhone list layouts inherit the native `Section` header typography. Optional aggregate values use secondary monospaced caption text, and the Info button remains a separate trailing control. In the wide iPad/macOS current-state row, Now and Overview reserve the same platform minimum-interaction-height header slot so their visible titles and first card tops align even when only Overview has a trailing Info button; do not fake that alignment with an invisible button or a per-device offset. Do not add a local title font in an individual chart.

On iPhone, visualization backgrounds align to the same inset-grouped row boundaries as Overview and the other native sections. Their content keeps one 16 pt inset inside that boundary. Weekly Gross Time and every task heatmap remain independent rounded cards with at least 10 pt visual separation because iOS can merge consecutive native sections; they must not become one shared outer card or cards inside cards. Keep the system section row transparent, use the shared self-drawn card background, and expand that background from the native content column to the grouped-card edge. The section title stays on the native content column. On iPad and macOS, Weekly Gross Time and Activity Heatmaps form one leading-aligned visualization group. Below 1000 pt of actual content width, that group, Quick Start, Timeline, Forecast, and Countdown stay in reading-order single column. At 1000 pt and above, the visualization group uses a 678...748 pt leading column while Quick Start consumes the remaining 300...410 pt trailing column; the following row gives Timeline the flexible leading column and, when present, keeps Forecast/Countdown in a 360 pt trailing column. The chart region therefore remains bounded at the 720 pt chart width plus two 14 pt card insets without leaving the rest of a wide canvas blank or allowing auxiliary content to change chart geometry. Heatmap tiles use the measured horizontal-scroll viewport rather than a device class: choose the largest whole-point tile from 12...24 pt that fits the selected 5/14/27/53-week range, with 2/3/4 pt gaps as tiles grow. Never shrink below 12 pt to force a long range into the card; overflow initially reveals the newest dates and stays horizontally scrollable. A range that fits disables its local horizontal scroll and remains leading-aligned after reaching the 24 pt readability cap. Month labels use native collision resolution, while the range and intensity legend stay outside the scrolling plot. Do not introduce masonry, a third column, or a custom layout library for this hierarchy.

Acceptance: Today does not jitter when scrolling; active timer controls stay at least 44 pt; metrics do not dominate the first screen; normal-text screenshots show matching title hierarchy and symmetric card margins on iPhone, iPad, and macOS; large text keeps titles, paths, durations, stop actions, Quick Start labels, countdown dates, and the final list rows visible without overlap or tab-bar obstruction.

### Tasks

Keep `List` with flat visible rows from `TaskTreeFlattener`, native swipe actions for start/child/edit/archive, and a compact secondary line for parent path or running context — never a workflow status. Checklist progress sits on the trailing side only when there is enough width, otherwise below the title line. Category headers are native section headers, not custom drop targets. Reordering uses reliable native edit/menu flows before drag-and-drop is reintroduced. Tasks carrying legacy planned/active/completed raw values render as ordinary rows; archived branches and historical tombstones stay hidden. Acceptance: every visible task is an independent row for tap, context menu, and swipe; indentation is stable across expand/collapse; archiving or creating a task preserves the Tasks destination.

### Task Editor

`NavigationStack` + `Form` with `LabeledContent`, native `Picker`, `TextField`, `Toggle`, and toolbar save/cancel. The task estimate control stays explicit: 15-minute steps, zero as "not set," and a concise explanation that it estimates this task's own work while child forecasts remain separate. Reuse `SymbolColorPickerRow` for tasks, categories, checklist items, and Inbox suggestion visuals; checklist rows reuse one shared row component; macOS uses up/down controls for checklist ordering, iOS uses native move. Acceptance: long checklist text wraps; Return submits where the user expects submit; adding a checklist item creates a focused empty row; forecast source copy distinguishes explicit estimate from checklist evidence and stays readable at accessibility sizes.

### Analytics

Keep chart math in services and render `AnalyticsSnapshot`. Wrap chart sections in native section-like containers with consistent headers; use Swift Charts where it fits and custom drawing only for timeline and stacked activity; legends are native rows with swatches and labels. Today distribution shows task colors and does not collapse short tasks into one-pixel lines. Acceptance: Today/Week/Month share data semantics; empty states explain what data is missing; long task names do not overlap charts; the landing page keeps a small summary plus category navigation, and at accessibility sizes the range picker may become a menu instead of a clipped segmented control. After Analytics has displayed once, a cold Day/Week/Month switch keeps the period controls and section/card shells at stable positions while data rows use non-interactive system redaction; it never substitutes a large blank loading card or exposes old metrics under the new selection. The lightweight spinner owns a fixed layout slot so adaptive control layout does not oscillate during refresh.

### Pomodoro

Keep Plan and Task as labeled, discoverable controls; do not restore title/timer-face tap gestures as hidden selection shortcuts. Prefer native menus, buttons, progress, and text over custom hit testing, with every primary touch action at least 44 pt. Setup controls reflow under Dynamic Type instead of shrinking the timer or truncating task identity. The timer face stays presentational: durable phase, deadline, and ledger changes belong to the store/commands. Acceptance: the empty state explains why focus cannot start and exposes the next valid action; long localized Plan/Task names remain readable at Accessibility Extra Large; background/foreground reconciliation never creates a new focus segment without an explicit user action.

### Settings

macOS settings open as a settings window; iOS settings are a sheet or pushed page. Use native `Form`, grouped sections, `Toggle`, `Picker`, `TextField`, and `Button`. Reflow value and input rows vertically at accessibility Dynamic Type sizes and expose one clear VoiceOver label/value instead of reading decorative icons. Pair destructive button roles with explicit text, red title/icon treatment, and confirmation copy; color alone is never the warning contract. Keep debug/status-only information under About or Advanced, and write settings copy that explains the outcome, not implementation details. AI configuration keeps endpoint/API key/model and the finite DeepSeek `high`/`max` thinking-effort choice in one Test→Save draft; a native segmented `Picker` communicates that there are exactly two provider-supported values, and its footer explains that other model families ignore the DeepSeek-specific setting. Acceptance: iCloud settings are understandable to non-developers; API key/model/thinking settings are clearly marked and secure; destructive maintenance actions have confirmation text; sync feedback announces both state and explanation.

The macOS Settings category list uses native sidebar styling and reads `sidebarRowSize`, so its centered SF Symbol slot scales with the person's small, medium, or large Sidebar Icon Size preference. Category symbols stay monochrome, share one leading column, and center against the complete title/subtitle block; iOS and iPadOS retain their colored 28 pt category slots and touch-oriented spacing.

### Sidebar And Detail

Let `NavigationSplitView` own sidebar visibility; do not duplicate the system sidebar toggle. Task Detail is the single canonical selected-task surface; do not add a second inspector that diverges from it without a product need. Sidebar task rows are simple navigation rows, not mini task editors. Acceptance: collapsing the sidebar always leaves a native way to reopen it; collapsing and restoring preserves the current detail; selecting a task makes the detail destination clear.

## Terminology

Use product language, not internal implementation language.

Preferred terms:

- "Actual Time" or localized equivalent for wall-clock time when space allows.
- "Total Task Time" or localized equivalent for gross time when space allows.
- "Time Segment" should appear only in advanced edit/debug contexts.
- Production UI must not offer permanent tombstone cleanup: an offline CloudKit device could otherwise resurrect old rows. The destructive "Clean Deleted Records" action is limited to isolated Demo/UI Test stores, must describe the 90-day scope, and must never treat a temporarily missing parent as deletion evidence.

## Timeline Rules

The Today analytics timeline clips cross-day segments to today's bounds, then displays the visible range from the first visible segment start to the last visible segment end. Empty days fall back to the full day. This keeps dense work periods readable while still respecting midnight boundaries.

Bars should show only time position, duration, color, and the task symbol. Task title, parent path, and exact time range belong in rows below the chart. The timeline runs vertically in the compact shell and horizontally in the regular shell — a width decision, not a platform one, so an iPad in Split View and a narrow Mac window get the vertical axis for the same reason iPhone does.

紧凑纵向 Timeline 的 start、interior、end 时间文字统一从图表内容 leading edge 起排；lane 数量、gap 数量和本地化 `skipped` 胶囊宽度不得改变这条基准线。动态 gutter 仍负责完整容纳胶囊并把 plot 推到右侧；与胶囊纵向冲突的 interior tick 可以省略，但剩余时间文字不能横向移动或重新居中。

Today Timeline 的普通记录与 Apple Health 记录必须复用同一个响应式 record renderer：紧凑宽度都按时间、身份、来源/时长纵向重排，常规宽度都使用相同的时间列、标题列、来源 badge 和时长列。Apple Health 只在来源、已计数时长、只读动作包装上保留差异；不得按数据类型或“第一行”增加专属 padding、offset 或另一套 row。

Adjacent tasks with no visible gap should use different lanes so their bars remain distinguishable. The layout should still minimize lane count: if task A overlaps B and B overlaps C, but A does not overlap C, A and C can reuse the same lane.

## Task Lists

The task management screen must render each visible task as its own `List` row. Do not place an entire subtree inside one row, because iPhone context menus and swipe actions would attach to the parent subtree instead of the child task the user touched.

Children are shown by flattening the expanded task tree into visible rows with indentation. This preserves infinite nesting while keeping native row behavior: tap opens the task workspace, an explicit pencil opens that same destination directly in editing state, and any swipe/context actions remain attached to the exact row the user touched.

## Component Inventory

Keep and refine:

- `TaskVisuals`
- `ChecklistControls`
- `SettingsRows`, `SettingsActionRows`, `SettingsInputRows`, `SettingsPresentationModifiers`, `SettingsSyncFeedbackRow`
- `TaskSummaryRow`, `TaskIdentityRow`, `TaskTimerActionButton`
- `SectionHeaders`
- `TaskProgressViews`
- `LayoutPolicies`

Review before further reuse:

- `ActionControls`: make sure it wraps native button styles rather than inventing new ones.
- `DesignSystem.cardStyle`: limit use to repeated content or framed data.
- Metric/statistic presentation (e.g. `PhoneSummaryMetric`, `AnalyticsSummaryMiniMetric`, `AnalyticsMetricList` in features): avoid turning every statistic into a card; prefer native `LabeledContent` rows until a framed metric is justified.

Avoid adding:

- New custom button styles for one screen.
- New custom segmented controls.
- Custom modal chrome.
- Custom sidebar toggles.
- Custom row swipe gestures.

## Review Checklist

Before merging UI work, verify:

1. Is there a native component that already does this?
2. The affected iPhone portrait screens at the normal system text size, including their primary action, navigation, empty/error state, keyboard path, and localized copy — no clipping on the smallest iPhone width.
3. iPad landscape Today and Task Detail with the sidebar both visible and collapsed; split view keeps its destination/detail state across window widths.
4. macOS narrow minimum window and full-screen window.
5. Long task names, localized strings, and dynamic timer text wrap or truncate intentionally and do not overlap.
6. All tappable targets are at least 44 pt on touch platforms.
7. Row identities are stable during scrolling and animation.
8. Custom animation is necessary, or the system interaction speaks for itself.
9. Dark appearance when the change touches color, material, charts, elevation, or contrast.
10. The bottom of each affected iPhone list can scroll above the current system tab bar at the normal text size.
11. User-facing strings are localized in all three languages.

Keep existing low-cost accessibility semantics and adaptive layouts intact. Extreme Dynamic Type and VoiceOver are risk-triggered checks: add a dedicated accessibility batch only when a change directly alters text reflow, semantic labels/state, non-color cues, focus order, or an existing regression signal; do not repeatedly spend simulator/device resources on unrelated extreme-size coverage.

For each UI polish round, capture or manually inspect the affected normal-text-size flows — iPhone Inbox (empty, one suggestion, many items, dismissed suggestion), iPhone Today (no/one/multiple active timers), iPhone Tasks with nested tasks and long titles, Tasks and Task Detail with checklist progress plus a legacy completed raw task that remains usable and an archived branch that stays hidden, iPad landscape Today and Task Detail with sidebar visible and collapsed, macOS settings window and main split view, and Analytics Today with short, overlapping, and empty data. Add dark appearance, long localization, or large-text cases only when the changed layout or a reported regression makes them relevant. Visual-only changes are covered by this manual screenshot checklist rather than brittle source-string tests.
