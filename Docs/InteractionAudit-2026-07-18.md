# Interaction and Product Semantics Audit

Status: active implementation specification

Started: 2026-07-18

## Goal

Time Tracker must use one interaction grammar for selecting tasks, editing task
facts, reading time evidence, and navigating settings. A feature must not invent
another picker, card hierarchy, or hidden tap target when the same product
object already has a shared presentation.

The ordinary path is:

1. Capture work or choose an existing task.
2. Work from one task workspace instead of switching between read-only detail
   and a separate editor.
3. Read today's time as a visual sequence, with the same chart semantics in
   Analytics.
4. Review Analytics through plain-language questions and visibly actionable
   rows.
5. Configure optional behavior in a conventional, leading-aligned settings
   hierarchy.

## Shared interaction rules

- A task is always shown with the same icon, title, parent path, availability,
  hierarchy, and selected state.
- Task selection uses one shared hierarchical picker surface. Search filters
  that tree; it does not replace it with an unrelated flat row design.
- Task facts are edited in the task workspace. Modal editors remain only for
  creation, destructive confirmation, or a short transaction with a clear
  cancel/save boundary.
- Timeline charts and timeline records are two views of the same ledger facts.
  The chart communicates sequence and overlap; the rows retain exact values and
  record actions.
- Analytics landing rows state the question they answer, show a concrete value,
  and use a visible disclosure affordance.
- Settings navigation rows fill their column and align to its leading edge.
- Animation explains a value change. It must not introduce a second timer or
  invalidate an entire page once per second.

## External implementation review

The reference implementation is FlowDown at commit
`d5e6df0ad59a96d2964b1d72f3a6cb139557de1c`.

- FlowDown uses GlyphixTextFx through UIKit labels. Time Tracker will adopt the
  same changing-number behavior through a shared SwiftUI numeric-text
  transition, reusing the existing `TimelineView` clock source. This avoids a
  UIKit/AppKit bridge and keeps native macOS support.
- MarkdownView 4.1.7 fills a real missing capability and will render task-note
  previews. Editing remains a plain Markdown source editor so stored notes are
  portable text.
- AlertController 2.2.2 is iOS/macCatalyst UIKit-only and does not support this
  app's native macOS target or system destructive/cancel roles. The app keeps
  SwiftUI `alert`, `confirmationDialog`, and `sheet`, with typed scene-owned
  presentation state.
- FlowDown's 60 FPS streaming Markdown cache is specific to live LLM messages;
  static task notes do not copy that machinery.

## Checkpoint 1 — shared graphical day timeline

Status: completed and verified

Acceptance:

- Today and Analytics render their bars, axes, overlap lanes, and compressed
  idle gaps with the same `TimelineChart` component.
- Compact iPhone uses the vertical chart; regular iPad and macOS use the
  horizontal chart.
- Today keeps exact ledger rows and edit/delete actions below the chart.
- Active bars advance from one narrow, minute-level timeline invalidation; row
  duration labels keep their existing second-level narrow invalidation.
- The chart is decorative to assistive technology because the adjacent record
  rows expose the equivalent task, range, source, duration, and actions.
- Empty Today and empty Analytics use their existing native empty states.

Verification:

- Home, Analytics timeline, and source-layout contract suites pass.
- The signed generic iOS application build passes without disabling signing.
- No simulator was allocated for this source-and-build checkpoint.

## Audit findings being corrected

| Surface | Current conflict | Unified direction |
| --- | --- | --- |
| Today timeline | Exact records only; no visual sequence or overlap model | Shared graphical day chart followed by exact records |
| Analytics timeline | Separate feature-local drawing implementation | Shared chart component and Analytics-specific explanatory records |
| Inbox | Nested suggestion cards and controls dominate the capture list | Flat Things-style capture list with quiet metadata and contextual actions |
| Task detail/edit | Read-only destination opens a second modal form for the same object | One task workspace with explicit editing state |
| Pomodoro task selection | Flat picker duplicates the sidebar task hierarchy | Shared hierarchical task picker |
| Analytics landing | Abstract category names and values do not clearly promise navigation | Question-led labels, explanatory values, and visible disclosure |
| Settings | Category contents do not explicitly fill and lead-align the sidebar row | Full-width, leading-aligned navigation rows |

## Checkpoint 2 — conventional Settings category alignment

Status: completed and verified

- Both ordinary and large-text Settings category rows fill the navigation
  column and align their icon/title content to the leading edge.
- The whole native `NavigationLink` row remains the interaction target; the
  fix does not add a competing custom button or gesture.
- The Settings category contract suite passes on the signed macOS target.

## Checkpoint 3 — one task workspace for evidence and editing

Status: completed and verified

- Existing-task Edit actions route to the canonical task destination in editing
  state; they no longer open a competing sheet.
- The destination switches between the evidence list and the shared
  `TaskEditorPanel`, preserving explicit Save, dirty-draft discard confirmation,
  validation, and stale-draft reload.
- New-task creation remains modal because it is a bounded create/cancel
  transaction, but it reuses the same editor session component.
- While editing, the destination hides the system back action so a dirty draft
  cannot be silently popped. Cancel returns to evidence in place.
- Workspace contracts, functional task-route tests, the complete task UI
  contract suite, and source-layout boundaries pass on macOS.

## Checkpoint 4 — shared hierarchical task selection

Status: completed and verified

- Today and Pomodoro use one task-tree projection, one task identity row, and
  one hierarchy picker surface instead of separate flat lists.
- Today configures command semantics for start, switch, and explicit stop.
  Pomodoro configures single selection and closes after selection.
- Search uses the same indexed title/notes data and retains the parent path.
  Completed or blocked branches remain understandable but cannot start work.
- Projection tests, timer-picker contracts, Home/Focus/shared-component
  contracts, source-layout checks, and a signed generic iOS build pass.

## Checkpoint 5 — one changing-number treatment

Status: completed and verified

- Running ledger durations, Pomodoro setup durations, and the active Pomodoro
  countdown use one `AnimatedClockText`.
- The value change uses SwiftUI's native numeric content transition while
  retaining monospaced digits. Reduce Motion disables the transition.
- The component does not own a timer; existing narrow `TimelineView` schedules
  remain the only clock sources.
- The animated-clock contract, focused UI suites, source-layout checks, and
  signed generic iOS build pass.

## Checkpoint 6 — Markdown task-note previews

Status: completed and verified

- Task-note evidence renders through MarkdownView 4.1.7, pinned to the exact
  reviewed revision used by the FlowDown reference.
- The app owns a small SwiftUI adapter around `MarkdownTextView` so links use
  the platform `openURL` action and the rendered view reports its natural
  height inside the task workspace.
- The adapter creates a local `MarkdownTheme`; it does not mutate the package's
  process-wide default theme.
- Editing remains a raw `TextEditor`. Markdown is a portable note format, not a
  hidden rich-text storage model.
- Empty or whitespace-only notes remain absent from the evidence view.
- The Markdown dependency/adapter and source-layout contract suites pass on
  macOS. Both the AppKit and UIKit adapter branches compile in signed macOS and
  generic iOS application builds.
- No simulator was allocated for this source-and-build checkpoint.

## Checkpoint 7 — quiet, capture-first Inbox

Status: completed and verified

- Capture and open items now form one flat, plain list instead of separate
  floating groups. A quiet outlined plus identifies capture, while a distinct
  Add button owns submission and visibly disables invalid input; Return keeps
  the same submission behavior.
- Inbox rows reuse the checklist completion/editor control but suppress the
  unrelated decorative checklist icon. The title is the row's only primary
  content; completion, delete, and reorder remain native list actions.
- Automatic suggestions are secondary metadata under the title. Apply, dismiss,
  retry, and failure states remain visible and accessible without drawing a
  nested card inside every row.
- Completed captures disappear from the working list immediately and live
  behind a count-labelled disclosure that is collapsed by default.
- An empty open list always states that Inbox is clear, even when completed
  history is available below it.
- Verification passed for `InboxUIContractTests`,
  `SharedComponentsContractTests`, `CoreSourceLayoutTests`, and
  `LocalizationContractTests`, followed by a signed generic iOS build.
- The real iOS UI path for focusing capture, entering a valid item, submitting
  it, and returning focus to capture passed twice on an explicitly owned
  iPhone 17 Pro simulator. Empty and captured-list screenshots were exported
  for the operation guide. Simulator
  `96794599-F89A-4F10-ACEB-C7E8B72BE1C8` was then shut down and deleted; no
  owned app, UI runner, `xcodebuild`, `xctest`, or Booted device remained.

## Checkpoint 8 — atomic manual Inbox routing

Status: completed and verified

- Moving an open Inbox item into a task is now one store-scoped transaction,
  not a fabricated manual AI suggestion followed by a second write.
- The transaction reuses the existing checklist-add command, including fresh
  ordering and the standard default visual, then reuses Inbox soft deletion to
  retire the logical item, duplicate siblings, and their suggestions.
- A presentation baseline records the Inbox item's ID, mutation revision, and
  logical suggestion identity. The command validates that baseline and the
  destination task again under the shared write lock so an item or task changed
  while the user is choosing cannot be routed using stale UI state.
- Checklist creation, visual creation, Inbox removal, and suggestion cleanup
  commit or roll back together. Successful routing publishes both Inbox and
  checklist events, including affected task ancestors.
- Focused coordinator tests cover fresh ordering, default visuals, duplicate
  sibling cleanup, consumed-baseline replay, stale item and unavailable task
  rejection, full rollback after persistence validation failure, and a late AI
  response after manual routing. The focused macOS suites and signed generic
  iOS application build pass.
- This guarantees at-most-once routing within one store. Two offline devices
  could still route the same logical capture into different checklist UUIDs;
  strict distributed idempotency requires a persisted routing receipt/source
  identity and is reserved for a later schema checkpoint.
- No simulator was allocated for this domain-only checkpoint.

## Checkpoint 9 — one hierarchy picker for every single-task choice

Status: completed and verified

- Timer start/switch, Pomodoro setup, and manual Inbox routing now present the
  same `TaskHierarchyPickerSheet`. Feature-specific wrapper sheets were removed
  rather than restyling three copies.
- The picker owns typed single-selection contexts. Each context supplies its
  title, empty/search copy, accessibility identifiers, and selection semantics
  while retaining one tree projection, task identity row, path treatment, and
  availability policy.
- Scene-owned presentation state now carries one generic single-task
  transaction. Pomodoro's existing route forwards to it for compatibility, and
  the host dismisses only after the destination callback confirms success.
- Inbox captures a mutation baseline before presenting the picker and invokes
  the atomic routing command on selection. A stale or unavailable selection
  therefore leaves the picker open instead of pretending the item moved.
- Stable accessibility identifiers are scoped to the actual title field, menu,
  menu command, picker, search field, and selection rows. The list-row
  identifier no longer leaks through SwiftUI and overwrites every child
  control.
- The focused Inbox and shared-picker suites pass on macOS. All three main-app
  localizations pass property-list validation, and the generic iOS build passes
  with the Apple Development identity and provisioning profile intact.
- The real iPhone path passed for capture, More, Move to Task, shared hierarchy
  presentation, search, selection, atomic removal, and dismissal. Screenshots
  of the shared picker and the cleared Inbox were exported and visually
  reviewed.
- The explicitly owned iPhone 17 Pro simulator
  `6DEA613D-C126-4B1F-BE20-3D46799F3606` was terminated, shut down, and deleted.
  No owned app, extension, UI runner, `xcodebuild`, `xctest`, Simulator,
  Problem Reporter, or Booted device remained.

## Checkpoint 10 — question-led Analytics

Status: completed and verified

- The Analytics landing page now asks six concrete questions instead of
  presenting abstract category names. Every native `NavigationLink` row states
  the question, answers it with data from the selected range, and names the
  detail destination.
- The six destinations remain one native list and navigation model. The change
  does not add cards with competing tap gestures or a second category system.
- A range with no tracked time now presents one explicit empty Summary and the
  same no-recorded-time answer for every question. It no longer describes
  missing samples as `0%` quality or one meaningful signal.
- Summary labels explain that gross time sums task timers while elapsed time
  counts overlaps once. Daily average is explicitly per tracked day.
- User-visible Pomodoro analysis is named Focus Sessions. Historical range
  labels are the neutral Day, Week, and Month equivalents in all three
  localizations.
- Detail-section explanations appear before their chart or records. Unsupported
  “decision-ready” quality claims, the duplicate next-action signal, and the
  duplicate longest-run quality row were removed.
- The focused Analytics presentation and Core Analytics tests pass. The full
  `TaskUIContractTests` and `LocalizationContractTests` pass on the signed
  macOS target; all three main-app strings files pass property-list validation
  and key parity.
- A signed generic iOS build passes with
  `Apple Development: ZEXUAN GAO (PX46M259V3)`, the provisioning profile, and
  the embedded mobile provision intact.
- The normal-size iPhone path verifies all six combined question/answer/detail
  labels, scrolls the final row fully above system chrome, enters Time
  Patterns, and waits for the hourly distribution without fixed sleeps. The
  final run passed 1/1 on iOS 27.0.
- Three visually reviewed screenshots are exported under
  `/Users/aac6fef/.codex/visualizations/2026/07/18/019f73e0-9f28-7c42-99c7-9ad324848ca0/analytics-checkpoint-10-questions-verified`.
  Visual review also caught and corrected an overly faint Questions
  explanation and a screenshot taken before the period controls had settled.
- The explicitly owned iPhone 17 Pro simulator
  `D86BCCF3-FF2F-4810-8299-C6AFBDCD9B1E` was terminated, shut down, and
  deleted. All derived data and result bundles for the batch were deleted; no
  owned app, UI runner, `xcodebuild`, `xctest`, or Booted device remained.

## Checkpoint 11 — touch-sized Blossom color selection

Status: completed and verified

- The text color menu and always-expanded palette were removed. Task,
  category, Checklist, and Pomodoro editors now reuse one
  `SymbolColorPickerButton` and one `SymbolColorWell`.
- BlossomColorPicker is pinned to official revision
  `9a1ee3df309e37ae271362818dcdfdb072ea9611`. iOS/iPadOS reuse its Core
  blossom view, model, color data, brightness control, and hit testing inside
  a scene-owned SwiftUI popover; macOS uses the package's top-level presenter.
  No color-wheel or palette implementation was copied into the app.
- The collapsed color well and every visible petal are 44 pt. Inner and outer
  radii are 44/88 pt, so adjacent centers and the gap between rings are at
  least one full touch target apart. The resulting 340 pt popover fits the
  narrow iPhone SE portrait width.
- Color is a secondary disclosure beside the SF Symbols heading. With the
  software keyboard visible, the symbol viewport retains at least one complete
  44 pt row above the keyboard. Opening color, selecting a symbol, submitting
  search, or scrolling ends search focus.
- Manual selection preserves arbitrary sRGB colors as canonical six-digit hex;
  legacy three-digit values remain readable and normalize to six digits. AI
  output remains restricted to the reviewed 24-color allowlist.
- Selected symbols, Checklist completion marks, and Timeline icons choose a
  black or white foreground from the resolved background luminance, including
  Blossom's pastel colors in Dark Mode, with a 4.5:1 contrast floor.
- The final focused signed macOS suites passed 54/54. A follow-up run of the
  utility and accessibility suites after the legacy-color and contrast guards
  passed 16/16. The signed generic iOS application build passed with the Apple
  Development identity and provisioning profile intact.
- The real operation path passed 1/1 on both an iPhone SE (third generation)
  and an iPad Pro 11-inch (fourth generation), iOS/iPadOS 27.0. It covers
  software-keyboard clearance, the 44 pt color well, Blossom expansion,
  actual color selection, repeated-selection collapse, symbol search and
  selection, and Back preserving the outer title/color draft.
- Five visually reviewed screenshots are retained under
  `/Users/aac6fef/.codex/visualizations/2026/07/18/019f73e0-9f28-7c42-99c7-9ad324848ca0/symbol-picker-checkpoint-11-verified`.
  Both explicitly owned simulators were terminated, shut down, and deleted,
  and the temporary software-keyboard preference was restored.

The next Analytics checkpoint must make Focus Session records and current-task
forecasts obey, or explicitly opt out of, the selected historical range before
the detail pages can be considered semantically complete.

Further checkpoints, completed operation-path evidence, screenshots, and any
remaining limitations are appended as implementation proceeds.
