# User Feedback Task 95 — Native Reorder And Delete Gestures

Status: Complete

Source: [`Docs/userfeedback.md`](../../../userfeedback.md)

## Requested behavior

- Remove the Checklist row's always-visible up/down ordering controls.
- Remove the Checklist row's always-visible More menu.
- Keep direct native row reordering.
- Delete a Checklist row by swiping right on iOS/iPadOS or by long-press/right-click context menu.
- Audit other ordering surfaces and remove equivalent custom up/down controls where native drag already exists or can replace them.

## Scope found during the initial audit

- `ChecklistEditorRow` / `TaskChecklistEditorSection`
- `TaskCategoryOrderingSheet`
- `HomeQuickStartEditorViews`
- Focused UI tests and current behavior/design/testing documentation

Unrelated menus that own actions other than ordering/deletion remain outside this task.

## Native framework and dependency decision

Use SwiftUI `List`, `ForEach.onMove`, `swipeActions(edge: .leading, allowsFullSwipe: false)`,
and `contextMenu`. These are the platform-standard APIs for this interaction and make a
third-party list/gesture dependency unnecessary. This follows AD-011: a package may not
replace native SwiftUI list behavior without evidence that the native API is insufficient.

Internet references reviewed:

- Apple `onMove(perform:)`
- Apple `swipeActions(edge:allowsFullSwipe:content:)`
- Apple `contextMenu(menuItems:)`

## Acceptance checklist

- [x] No Checklist up/down buttons or More button remain at normal text size.
- [x] Checklist rows still reorder directly within their incomplete/completed group.
- [x] iOS/iPadOS exposes Delete from a leading-edge swipe, which is a rightward swipe in left-to-right locales; full swipe remains disabled.
- [x] A Checklist long press on touch platforms and right-click on macOS exposes Delete.
- [x] Category ordering has native drag but no custom up/down buttons.
- [x] Quick Start pinned ordering has native drag but no custom up/down buttons.
- [x] Stable item/task/category identities and existing durable command boundaries are unchanged.
- [x] Focused behavior/UI tests pass and normal-size screenshots are visually reviewed.
- [x] `make test`, formatting, localization parity, signed builds, and Release all-device installation pass.
- [x] Every simulator/process owned by this task is released.

## Checkpoints

1. Claim task, create this durable memory, and audit equivalent controls.
2. Add/update behavior-facing UI acceptance tests before production wiring.
3. Replace custom controls with native gestures and update current documentation.
4. Verify and commit the implementation checkpoint.
5. Install the frozen Release build on every configured device, mark feedback complete,
   remove the active link, and commit task closeout.

## Sub-agent coordination

- `audit_controls` completed a read-only inventory. It confirmed that Checklist, Category
  ordering, and Quick Start are the only production surfaces with explicit up/down
  ordering buttons. It also confirmed that Inbox, Timeline, task/category action menus,
  and draft recovery menus own unrelated real actions and must remain.
- `audit_tests` completed a read-only test review. It confirmed existing durable
  Checklist and Category reorder coverage, identified the missing Quick Start
  visible-identity move test, and documented that synthesized native row lift is not a
  reliable iOS 27 XCTest gate. The accepted matrix therefore combines behavior tests,
  absence assertions, real swipe/context-menu interaction, and screenshots.
- The primary agent owns all edits, builds, simulators, screenshots, commits, and device
  installation.

## Progress log

- 2026-07-29: Preserved the user's `Docs/userfeedback.md` change and reverted the only
  other unstaged edit (`.gitignore`).
- 2026-07-29: Reviewed repository instructions, Apple HIG, SwiftUI expert guidance,
  project architecture/code/UI/testing/localization guidance, and native Apple API
  documentation. Initial source audit found the three surfaces listed above.
- 2026-07-29: Added the Quick Start visible-identity move tests first. The first focused
  run failed as expected because `movingVisibleSelections` did not exist.
- 2026-07-29: Removed the three custom arrow implementations and the Checklist More
  menu; wired leading swipe/context-menu Delete and native Quick Start `onMove`; removed
  the now-unused three-language Move Up/Move Down strings; updated current docs.
- 2026-07-29: The focused Quick Start mutation suite passed 8/8 after implementation.
- 2026-07-29: The focused Task editor session suite passed 25/25 and the scoped
  category command coordinator suite passed 14/14, covering durable Checklist and
  category reorder/delete behavior after a fresh reload.
- 2026-07-29: Formatting, format lint, localization parity, and hook installation
  checks passed.
- 2026-07-29: iPhone UI tests passed for Checklist long-press/context-menu Delete,
  leading-edge swipe Delete, category native sorting, and Quick Start native sorting.
  An iPad Pro UI test passed for complete long-title growth, control centering, and
  absence of the Checklist More control. All five generated screenshots were exported
  and visually reviewed.
- 2026-07-29: Two macOS UI-test starts were blocked before test execution by
  `LocalAuthentication` reporting `System authentication is running`. A read-only
  Computer Use inspection found no actionable authentication window. Signed macOS
  unit/build verification remains the macOS gate for this checkpoint; the UI-runner
  environment failure is retained as explicit evidence.
- 2026-07-29: All temporary iPhone/iPad simulators created by the Makefile were shut
  down and deleted; no owned simulator remains Booted.
- 2026-07-29: The first full `make test` run was interrupted after an unrelated
  async snapshot-worker test stopped making progress. Its focused 9-test suite then
  passed in 0.558 seconds, and a clean full rerun passed all 1,574 tests in 176 suites
  in 52.646 seconds.
- 2026-07-29: Committed the implementation checkpoint as `b491de17`; the commit hook
  advanced the app to 1.1.351 (406).
- 2026-07-29: `CONFIGURATION=Release make build-install-all` succeeded. The signed app,
  with its embedded Watch companion, was installed on `iPad Pro M4` and `iPhone Air`;
  the paired Watch receives the companion through automatic app install. The signed
  macOS app was copied to `/Applications/timetracker.app` and passed on-disk signature
  validation.
