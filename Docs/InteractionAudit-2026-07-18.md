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

Further checkpoints, completed operation-path evidence, screenshots, and any
remaining limitations are appended as implementation proceeds.
