# 2026-08-11 Animation Review — Implementation Memory

Status: Complete

Task source: user-requested project-wide animation review

## Objective

Make the app's motion quieter, more consistent, and more informative without
adding a new animation system or changing product behavior.

The repository currently has 22 explicit SwiftUI motion call sites in 14
production files, plus BlossomColorPicker's package-owned bloom animation.
The useful motion is concentrated around numeric timers, checklist state,
Inbox suggestion state, list selection/reordering, and the AI request-to-review
handoff. Two cross-cutting effects are decorative rather than explanatory: the
custom page lift on every compact tab appearance and the sidebar task-selection
pulse.

This batch:

- remove the custom compact-tab page lift and sidebar selection pulse, leaving
  native tab/navigation behavior in charge;
- replace the regular-shell destination's unconditional trailing slide with a
  restrained fade;
- use a small shared timing vocabulary for existing app-owned state,
  structural, and press feedback;
- animate only disclosure chevrons instead of implicitly animating whole list
  height changes;
- add restrained press/state feedback to the shared timer action and a local
  entrance/exit transition to the rare sync-conflict notice.

Explicit non-goals: animating charts, scroll position, list identity, live
resize, root-shell breakpoint changes, native navigation, every data refresh,
Widget/Live Activity/Watch elapsed clocks, or adding a user animation setting,
dependency, phase animator, keyframe animator, matched geometry, or custom
animation coordinator. Changing BlossomColorPicker's package-owned bloom,
collapse, or macOS close timing is also out of scope.

## Acceptance checklist

- Compact tabs use the platform transition only; tab contents do not replay a
  second fade/lift and retain their navigation/scroll state.
- Regular sidebar destination changes do not imply a false forward-navigation
  direction and remain interruptible when destinations change quickly.
- Task/category/Inbox disclosure chevrons clearly reflect expanded state,
  while row insertion/removal is not wrapped in a broad explicit animation.
- Shared timer icon buttons retain existing size, destructive semantics, and
  accessibility identifiers; press feedback is subtle and consistent.
- A newly surfaced or dismissed sync-conflict notice preserves spatial context
  without affecting its review/dismiss behavior.
- With Reduce Motion enabled, app-owned translation/scale motion is removed;
  the sync notice uses opacity only and numeric timers remain static.
- iPhone normal-text Today, Tasks, Inbox, timer picker, and the sync-conflict UI
  fixture remain readable and hittable. iPad regular-shell destination changes
  and hierarchy disclosure remain stable.
- No animation is added to Watch, Widget, Live Activity, Analytics charts,
  scrolling, live resize, or one-second page-wide refresh paths.

## Test record

No production behavior, durable data, or schema is changing, so no permanent
regression test was added. Animation quality and Reduce Motion are visual/system
behavior covered by this acceptance checklist plus existing stable XCUITest
paths; exact timing, pixels, and private SwiftUI hierarchy will not become
automated contracts.

After reviewing the result, the user chose to retain BlossomColorPicker's
original bloom/collapse animation and the macOS presenter's 350 ms close delay.
The app-level Reduce Motion override was removed without changing the other
animation work; no timing or pixel-level regression contract was added. The
follow-up passed formatting and localization checks, all 194 unit tests, and
signed iOS and macOS builds. It did not create a simulator or run macOS UI
automation on the user's active desktop.

A temporary `TEST-SCAFFOLD` method,
`AdaptiveShellUITests.testAnimationReviewFlow`, drove system-tab switching, task
disclosure, the shared task-detail timer action, Inbox completed disclosure, and
timer-picker hierarchy disclosure with condition-based waits and screenshots.
The successful owned run captured the available task disclosure, timer stop,
and picker disclosure states. The fixture had no completed Inbox rows, so that
optional branch was correctly skipped. The method was then deleted in full; no
test-source change or scaffold marker remains.

Final verification used `make format-check`, `make localization-check`,
`make test`, signed iOS/macOS builds, and explicitly owned iOS Simulator UI
runs at normal text size. Xcode's installed `simctl ui` exposes appearance,
contrast, and content size but no supported Reduce Motion toggle, so the Reduce
Motion branches were reviewed at every app-owned motion call site and compiled
for both platforms rather than claiming a runtime toggle test. No configured
macOS VM or VM runner is present; macOS UI automation was therefore not run on
the user's active desktop.

## Verification and resource ownership

- Record every simulator UDID and result bundle created by this task.
- Terminate the tested app/runner, shut down and delete task-created simulators,
  and verify no owned `xcodebuild`, `xctest`, UI runner, or Booted device remains.
- Move deleted source files and disposable result artifacts to the macOS Trash.

### Simulator evidence

- `C6106922-38C3-447A-B94E-7A2B08867E1E`: first temporary run reached the
  Tasks tab, then the scaffold called macOS-only `click()` on iOS. The test code
  was corrected to touch input; the owned simulator was terminated and deleted.
- `B2F76715-C7D7-42FB-AA99-7D98BCDF2095`: a retry encountered the iOS 27 beta
  floating-tab identifier not surfacing. Its recording confirmed the five tabs
  and Today content were rendered normally. The scaffold switched to the
  forced-English system button labels; the owned simulator was terminated and
  deleted.
- `3EFDC7E6-35F3-44CF-A14C-151E1E25742C`: the corrected focused flow passed
  1/1 in 51.7 seconds. The three retained attachments were manually inspected
  at normal text size and showed stable expanded hierarchy geometry, the Stop
  state in Task Detail, and expanded timer-picker hierarchy. The Make target
  terminated the app and deleted the simulator.
- `9F08BC3A-FF0E-4EE0-A931-214007977C92`: after deleting the temporary test,
  the retained `AdaptiveShellUITests` iOS suite passed 2/2. The Make target
  terminated the app and deleted the simulator.

The two failed disposable result bundles were moved to
`~/.Trash/timetracker-animation-ui-failed-runs-20260811/`. Successful focused
evidence and exported screenshots were moved to
`~/.Trash/timetracker-animation-ui-passed-evidence-20260811/`; the retained-suite
result was moved to
`~/.Trash/timetracker-animation-ui-retained-suite-20260811/`. The removed source
files are recoverable under
`~/.Trash/timetracker-animation-source-removals-20260811/`.

### Final gates

- `make build-ios`: passed, including embedded Watch, Widget, and Live Activity
  products under automatic signing.
- `make build-macos`: passed under automatic signing, including the AppKit
  Blossom presenter.
- `make test`: 194 tests in 35 suites passed.
- `make format-check`: 0/720 files require formatting.
- `make localization-check`: 9/9 resources passed parity.
- `make check-hooks`: tracked hooks are active.
- Final audit: no temporary test/source change or scaffold marker in test
  sources, no owned `xcodebuild`/`xctest`/UI runner, and no owned or Booted
  simulator remains.
