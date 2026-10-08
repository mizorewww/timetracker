# UI Design Notes

Status: current UI guardrails

Current user behavior is in [User Guide](UserGuide.md); verification rules in [Testing](Testing.md); implementation/UI contracts in [CodeGuide](CodeGuide.md). This document defines how UI work moves toward native Apple components and away from fragile custom drawing.

The app should feel like a first-party Apple productivity tool: calm hierarchy, native navigation, predictable controls, system gestures, readable compact layouts, minimal custom animation, and no layout surprises when text, width, or localization changes.

Layout adapts to **width, never to device model**. `AppRootView` measures the window and picks one of two shells — compact (tab bar) below 720 pt, regular (sidebar + detail) at or above it — and publishes the choice as `\.layoutShell`. Today may coalesce intermediate widths to 8 pt steps, but 720, 800, 1056, and the 1236 pt viewport cap stay exact. Do not reintroduce `UIDevice.current.userInterfaceIdiom` or an `os(...)` branch to make a layout decision; `#if os(...)` is for APIs that exist on only one platform, and touch-target sizing stays platform-keyed because it encodes input modality, not width. Custom drawing is allowed only when the product concept requires it (analytics timelines, activity distribution charts); editors, lists, settings, menus, sheets, and navigation are native-first.

## Principles

- Prefer native `NavigationSplitView`, `NavigationStack`, `List`, `Form`, `Table`, sheets, popovers, menus, `Menu`, `Picker`, and toolbar items before custom controls; do not add a custom sidebar toggle (the split view owns it).
- Cards are for repeated content or framed data, not every section; avoid cards inside cards.
- Today answers three questions quickly: what is running, what happened today, what can continue next.
- Forecast UI explains its source: an `info.circle` entry point, a short source label, and a plain-language reason. An explicit task estimate is a valid source without checklist evidence; otherwise do not show a numeric forecast until checklist progress and tracked time are sufficient, and never imply recent pace created the remaining amount.
- Checklist UI belongs inside task editing/detail as progress markers under a timed task, not as timed subtasks. Rows behave like native to-do rows: a large circular check button, ≥44 pt row height on touch, unfinished first, completed after with strikethrough. Every control centers against the complete wrapped title block; task-checklist titles have no arbitrary line cap (Inbox keeps its compact bound). Adding an item creates a focused empty row. Completion is the task's only product-level progress signal and never disables later work.
- Do not show a task workflow-status picker, badge, Complete/Reopen action, or ordinary task Delete action. Legacy planned/active/completed raws are invisible compatibility data; archived branches hide and recover through Restore; historical tombstones are a sync boundary, not a second UI lifecycle.
- iPhone layouts split dense rows into two lines when icon, title, path, timer, and actions cannot fit.
- Task Detail is the one canonical deep surface on iPhone/iPad/macOS; do not add a second drifting inspector. For an ordinary task its identity icon is an icon-only navigation affordance beside an editable title (44 pt icon target, 14 pt title gap, disclosure indicator hidden).
- Sheets use system `NavigationStack` + `Form` + toolbar cancel/save; fixed sheet sizes are macOS-only.
- The analytics timeline separates graphic bars (time/color/icon) from task text in rows below. When a section shows every item, do not show inert "All" links; a disclosure affordance only appears when it acts.
- Expensive derived values are passed into rows, not recalculated. User-facing copy explains outcomes, not internal model names.
- Shared styling and controls follow the SharedUI second-caller rule in [CodeGuide](CodeGuide.md).

## Typography

Use system semantic text styles as the scale. On macOS, user-facing identity, answers, explanations, status, warnings, and action labels use `body`/`callout` by information role; reserve `subheadline`/`caption`/`footnote` for genuine metadata (paths, timestamps, badges, counts, chart axes, ranges, provider IDs, build details). A forecast reason, insight explanation, sync/error message, or empty-state instruction can affect the next decision and is not metadata. Cross-platform components use the same semantic style for the same product role; density differences belong to an explicit component style or the compact/regular shell, not an `os(...)` font branch. Do not apply a root font environment, fixed point-size override, global scale, `minimumScaleFactor` compression, or third-party typography framework. SF Symbols that identify a row/header inherit its semantic font.

## Motion

Motion explains a local state change or preserves spatial context, never page decoration. System tabs/navigation/sheets/popovers/menus/window resizing own their transitions; compact tab content must not replay a custom entrance, regular sidebar destinations are peers (brief crossfade only), and disclosure controls rotate their chevron without wrapping list insertion/removal in a broad animation. App-owned motion uses `AppMotion`, stays on opacity/render transforms, and stays local, interruptible, and tied to the changed value. Reduce Motion removes custom translation/scale, keeps at most restrained opacity, and keeps numeric timers static. BlossomColorPicker retains its package-owned bloom/collapse. Do not add custom motion to scrolling, row identity, charts, live resize, one-second page-wide refresh, Watch Always-On content, Widget, or Live Activity.

## Native-First Rules

| Need | Prefer |
| --- | --- |
| Screen navigation | `NavigationStack`, `NavigationSplitView`, `TabView`, `.inspector` |
| Dense item list | `List`, `Section`, `ForEach`, `swipeActions`, `contextMenu` |
| Editing structured data | `Form`, `LabeledContent`, `Picker`, `Toggle`, `TextField`, `DatePicker`, toolbar cancel/save |
| Settings | `Form` in a macOS settings window; pushed page or sheet on iOS |
| Finite choice / context actions | `Picker` (menu/inline/segmented by space); `Menu`, `contextMenu`, native toolbar |
| Primary/secondary actions | `Button` with `.borderedProminent`/`.bordered`; `.plain` only for icon-only affordances |
| Progress / search / disclosure / reorder | `ProgressView`; `.searchable`; `DisclosureGroup` for simple content only; `List` `onMove` or native edit mode |

Avoid: hand-drawn duplicates of system controls; invisible text in compact buttons; `ScrollView` containing a fixed-height `List` without a design note; custom sidebar toggles; animation on scroll-title size, row identity, or list height; cards inside cards; color as the only meaning; keeping a dense horizontal row at Accessibility sizes when a vertical composition or native menu preserves the full title/value/action.

## Screen Notes

### Inbox
One native `List` with native row behaviors; capture, open, completed, and suggestion feedback live in native sections. Open items reorder by long-press drag without a separate Sort/Edit mode; capture and completed rows stay outside that scope. The capture row behaves like a native text field (submit clears and refocuses). Acceptance: no horizontal clipping on the smallest iPhone width; swipe actions stay visible after suggestion dismissal; capture and navigation actions do not compete.

### Today
iPhone Today is a native priority-ordered `List` (Now, Overview, Weekly Time, Activity Heatmaps, Quick Start, Timeline, Forecast, Countdown). Use the native large title, keep the gross/wall summary compact, and use system buttons for Start Timer / New Task. The global timer-picker launcher is one shared native leading-aligned row across shells: empty Start Timer, parallel Start Another Timer, and exclusive Switch Timer change only their mode-derived title/icon, never prominence or structure; empty Quick Start reuses it. Section hierarchy has one owner: `HomeSectionHeader` renders card titles with `.headline` and lets iPhone list `Section` inherit native header typography; optional aggregate values use secondary monospaced caption, with Info as a separate trailing control. Weekly Time uses a common zero baseline and side-by-side Gross (left, green) / Wall (right, blue) bars with a text legend; compact charts are 190 pt, regular cards 210 pt. In the wide current-state row, align Now/Overview by taking the taller card's ideal height and centering the Overview metrics — never with invisible buttons, measured minimum heights, magic padding, or per-device offsets. On iPhone, visualization backgrounds align to the same inset-grouped row boundaries with one 16 pt inner inset, remain independent rounded cards with ≥10 pt separation, and must not become one shared outer card. Weekly Time + Activity Heatmaps form one leading-aligned group; below 1000 pt content width all sections stay single-column; at ≥1000 pt the group takes a 678...748 pt leading column with Quick Start in the remaining 300...410 pt, and Timeline pairs with an optional fixed 360 pt Forecast/Countdown column. Heatmap tiles fit the measured viewport (12...24 pt whole points for 5/14/27/53-week ranges, 2/3/4 pt gaps), never below 12 pt; overflow reveals the newest dates and stays scrollable; month labels use native collision resolution. Acceptance: no scroll jitter; active timer controls ≥44 pt; metrics do not dominate the first screen; normal-size screenshots show matching hierarchy and symmetric margins across iPhone/iPad/macOS.

### Tasks
Keep `List` with flat visible rows from `TaskTreeFlattener`, native swipe actions for start/child/edit/archive, and a compact secondary line for parent path or running context — never a workflow status. Checklist progress sits trailing only when there is width, otherwise below the title. Category headers are native section headers, not custom drop targets. Reordering uses reliable native edit/menu flows before drag-and-drop. Tasks with legacy planned/active/completed raws render as ordinary rows; archived branches and historical tombstones stay hidden. Acceptance: every visible task is an independent row for tap/context menu/swipe; indentation is stable across expand/collapse; archiving or creating preserves the Tasks destination.

### Task Editor
`NavigationStack` + `Form` with `LabeledContent`, native `Picker`, `TextField`, `Toggle`, toolbar save/cancel. The estimate control stays explicit: 15-minute steps, zero = "not set", and a concise note that it estimates this task's own work while child forecasts remain separate. Reuse `SymbolColorPickerRow` for tasks, categories, checklist items, and Inbox visuals; on macOS Blossom must bloom from the center of the actual color well even inside the SF Symbols popover (only edge clamping may move it), never positioned through the app key window. Checklist rows reuse one shared component and reorder by long-press drag within the incomplete/completed group. Destructive delete has no permanent trash/More button: iOS/iPadOS expose one leading-edge swipe action with full-swipe disabled (revealed by a rightward swipe in LTR), and long press / macOS right-click expose the same command via context menu. Category ordering and Quick Start pinning follow the same native-drag/no-arrow rule. An automatic checklist visual update merges icon/color into the existing row without replacing the draft or text field, preserving insertion point, keyboard, and any manual choice. Acceptance: long checklist text grows beyond four lines without inner scrolling with controls centered against the whole block; direct reordering and stable-identity deletion persist after save; AI visual completion never interrupts typing.

### Analytics
Keep chart math in services and render `AnalyticsSnapshot`. Wrap chart sections in native section-like containers with consistent headers; use Swift Charts where it fits, custom drawing only for timeline and stacked activity; legends are native rows. Today distribution shows task colors and does not collapse short tasks into one-pixel lines. After Analytics has displayed once, a cold Day/Week/Month switch keeps period controls and section/card shells stable while data rows use non-interactive system redaction (never a large blank loading card or old metrics under a new selection); the lightweight spinner owns a fixed layout slot. Activity Heatmaps are one discoverable landing row opening a standalone native page that reuses the shared task Heatmap cards, keeps the Settings range, does not repeat the Analytics date filter, and shows a native configuration empty state. Acceptance: Day/Week/Month share semantics; empty states explain missing data; long task names do not overlap charts; the range picker may become a menu at accessibility sizes instead of a clipped segmented control.

### Pomodoro
Keep Plan and Task as labeled, discoverable controls; do not restore title/timer-face tap gestures as hidden selection shortcuts. Prefer native menus/buttons/progress/text over custom hit testing, with every primary touch action ≥44 pt. Setup controls reflow under Dynamic Type instead of shrinking the timer or truncating task identity. The timer face stays presentational: durable phase/deadline/ledger changes belong to the store/commands. Acceptance: the empty state explains why focus cannot start and exposes the next valid action; long Plan/Task names stay readable at large sizes; background/foreground reconciliation never creates a focus segment without explicit user action.

### Settings
macOS settings open as a settings window; iOS settings are a sheet or pushed page. Use native `Form`, grouped sections, `Toggle`, `Picker`, `TextField`, `Button`. Reflow value/input rows vertically at accessibility sizes and expose one clear VoiceOver label/value instead of reading decorative icons. Pair destructive button roles with explicit text, red treatment, and confirmation copy; color alone is never the warning contract. Keep debug/status info under About or Advanced, and write copy that explains outcomes. AI configuration keeps endpoint/API key/model and the DeepSeek `high`/`max` effort in one Test→Save draft, with a native segmented `Picker` and a footer noting other model families ignore the DeepSeek setting. The macOS Settings category list uses native sidebar styling and `sidebarRowSize` (symbols monochrome, one leading column, centered against the full title/subtitle block); iOS keeps its colored 28 pt category slots.

### Sidebar And Detail
Let `NavigationSplitView` own sidebar visibility. Sidebar task rows are simple navigation rows, not mini editors. Acceptance: collapsing the sidebar always leaves a native way to reopen it; collapse/restore preserves the current detail; selecting task B while A is open replaces the highlight and detail in one activation without exposing the Tasks root; a dirty A draft stays selected when discard is cancelled.

## Timeline And Task Lists

The Today timeline clips cross-day segments to today's bounds and displays from the first visible segment start to the last visible segment end; empty days fall back to the full day. Bars show only time position, duration, color, and task symbol; title, parent path, and exact range belong in rows below. The timeline runs vertically in the compact shell and horizontally in the regular shell — a width decision, so an iPad in Split View and a narrow Mac window get the vertical axis for the same reason iPhone does. In the compact vertical timeline, start/interior/end time labels all align to the chart leading edge regardless of lane count, gap count, or localized `skipped` capsule width; interior ticks that collide with the capsule may be omitted, but remaining time labels must not move. Today timeline records reuse one responsive renderer (compact stacks time/identity/source+duration; regular uses the same time/title/source-badge/duration columns). Analytics timeline and Task Detail history rows are full native buttons with a trailing pencil that open the same `SegmentEditorSheet` (tracked-segment identity only).

The task management screen renders each visible task as its own `List` row (never an entire subtree in one row, so iPhone context menus/swipes attach to the touched child) by flattening the expanded tree into indented rows.

## Component Inventory

Keep and refine: `TaskVisuals`, `ChecklistControls`, `SettingsRows`/`SettingsActionRows`/`SettingsInputRows`/`SettingsPresentationModifiers`/`SettingsSyncFeedbackRow`, `TaskSummaryRow`, `TaskTimerActionButton`, `SectionHeaders`, `LayoutPolicies`. Review before further reuse: `ActionControls` (must wrap native styles), `DesignSystem.cardStyle` (repeated/framed content only), and metric/statistic presentation (prefer native `LabeledContent` rows until a framed metric is justified). Avoid adding new one-screen button styles, custom segmented controls, custom modal chrome, custom sidebar toggles, or custom row swipe gestures.

## Review Checklist

Before merging UI work:

1. Is there a native component that already does this?
2. Affected iPhone portrait screens at normal text size, including primary action, navigation, empty/error state, keyboard path, and localized copy — no clipping on the smallest width.
3. iPad Today and Task Detail above/below the 720 pt breakpoint; destination/detail state survives the switch.
4. macOS below-720 pt compact window and wide regular window; native Settings and menu behavior retained.
5. Long task names, localized strings, and dynamic timer text wrap/truncate intentionally without overlap.
6. All tappable targets ≥44 pt on touch.
7. Row identities stable during scroll/animation.
8. Custom animation is necessary, or the system interaction speaks for itself.
9. Dark appearance when the change touches color, material, charts, elevation, or contrast.
10. The bottom of each affected iPhone list scrolls above the current tab bar at normal text size.
11. User-facing strings localized in all three languages.

Keep existing low-cost accessibility semantics and adaptive layouts intact. Extreme Dynamic Type and VoiceOver are risk-triggered checks: add a dedicated accessibility batch only when a change directly alters text reflow, semantic labels/state, non-color cues, focus order, or an existing regression. For each polish round, inspect the affected normal-text-size flows (iPhone Inbox states, Today with 0/1/multiple timers, nested Tasks with long titles, checklist progress + a legacy completed raw task + a hidden archived branch, iPad landscape Today/Task Detail with sidebar visible and collapsed, macOS settings + split view, Analytics Today with short/overlapping/empty data); add dark appearance, long localization, or large-text cases only when relevant. Visual-only changes are covered by this manual screenshot checklist rather than brittle source-string tests.
