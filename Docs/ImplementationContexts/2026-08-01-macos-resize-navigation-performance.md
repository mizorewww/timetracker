# macOS Resize and Navigation Performance — Implementation Memory

Status: complete

Started: 2026-08-01

## Objective

Remove the visible stalls in the macOS app when the user rapidly resizes the
main window or rapidly changes primary sidebar destinations. Preserve the
adaptive compact/regular shell, navigation safety, current page behavior, and
the existing data/read-model boundaries.

## Performance context

- `AppRootView` currently writes measured width into root `@State` for every
  change greater than 0.5 pt even though shell selection only changes at 720 pt.
- `DesktopMainView` independently writes every width change greater than 0.5 pt;
  its body constructs the Today presentation and supplies layout-dependent
  closures to chart/list sections.
- `DesktopContentView` switches between complete destination-specific
  `NavigationStack` values, recreating navigation infrastructure on every
  primary selection.
- Task-tree and Analytics projections already have revision-keyed caches or
  asynchronous loaders. The scan found no View-owned Foundation timers,
  synchronous View-body file I/O, image processing, `AnyView`, unstable
  `ForEach` identity, or legacy `ObservableObject` fan-out.
- The baseline uses a signed Release build, an isolated `--uitesting` in-memory
  store, host-Mac SwiftUI Instruments, scripted width changes across the shell
  breakpoint, and scripted sidebar selection.

## Acceptance checklist

- [x] Root shell measurement mutates view state only on first measurement or
      when the width crosses the shell breakpoint; same-side resize events are
      ignored.
- [x] The Today layout coalesces sub-visual width changes into an 8 pt visual
      tolerance, caps measurements once content reaches its maximum width, and
      still applies every responsive breakpoint exactly.
- [x] The regular detail column keeps one stable navigation container while its
      destination content changes; task-detail navigation and compact-shell
      navigation behavior remain unchanged.
- [x] Unit tests cover the resize-update policy at exact boundaries and verify
      that a rapid same-side width sequence produces bounded state writes.
- [x] Existing adaptive-shell XCUITests still prove compact and regular shell
      wiring at representative Mac widths.
- [x] `CorePerformanceBudgetTests`, the complete signed macOS unit suite,
      SwiftFormat, localization parity, and a signed Release macOS build pass.
- [x] A same-scenario post-change Release SwiftUI trace is compared with the
      baseline for hangs, hitches, update count/duration, and the dominant
      invalidation sources.
- [x] Every owned app, trace writer, test runner, and temporary profiling
      artifact is released or documented at closeout.

## Evidence log

- 2026-08-01: Static Axiom scan covered all SwiftUI bodies, collection
  containers, identity, geometry, environment writes, navigation paths,
  formatters, synchronous I/O, image work, timers, and legacy observation.
- 2026-08-01: Baseline Release trace
  `/tmp/timetracker-before-actions-20260801-1551.trace` recorded four rapid
  1180↔700 pt resize cycles followed by fifteen primary-page selections. Trace
  analysis found 550,162 SwiftUI updates / 2,710 ms, 16,997 view-body updates,
  156 `DesktopMainView` updates / 31 ms, 715,582 cause-graph edges, 540
  `NavigationSplitRepresentable` updates / 19 ms, 3,527 ms sampled CPU, zero
  hangs, and zero animation hitches in 20.63 seconds.
- 2026-08-01: Final signed Release trace
  `/tmp/timetracker-after-final-actions-20260801-1623.trace` repeated the exact
  scenario against the frozen implementation. It found 405,169 SwiftUI updates
  / 2,144 ms, 13,864 view-body updates, 110 `DesktopMainView` updates / 21 ms,
  502,562 cause-graph edges, 357 `NavigationSplitRepresentable` updates / 11 ms,
  2,841 ms sampled CPU, zero hangs, and zero animation hitches in 20.63 seconds.
  Relative to baseline, updates fell 26.4%, SwiftUI update time 20.9%, Today
  root recomputation 29.5%, cause propagation 29.8%, navigation representable
  updates 33.9%, and sampled CPU time 19.4%.
- 2026-08-01: The macOS navigation XCUITest passed fifteen consecutive primary
  destination changes plus Analytics-detail → Today path reset. The six-test
  architecture suite passed the exact breakpoint and bounded-write policies.
- 2026-08-01: `CorePerformanceBudgetTests` passed 15/15 and the complete signed
  macOS unit gate passed 1,584 tests in 176 suites. The gate initially exposed a
  forecast fixture fixed at 2026-05-01 that had aged outside the production
  90-day window; changing the fixture to yesterday at noon made the focused
  forecast suite pass 14/14 without changing production behavior.
- 2026-08-01: The complete macOS `AdaptiveShellUITests` suite passed 4/4 after
  its launch helper explicitly activated the app before interactions and
  terminated every tested process at teardown. The retained run exercised the
  compact native Settings scene, shell selection, Today's Now section, the
  Analytics path reset, and fifteen primary destination changes.
- 2026-08-01: The final signed Release macOS build and signed generic iOS build
  succeeded. SwiftFormat reported 0/875 files requiring formatting,
  localization parity passed 9/9 resources, and `git diff --check` passed.
- 2026-08-01: Cleanup moved all owned Instruments traces/analyses, temporary
  profiling apps/screenshots, and intermediate UI result bundles to the
  recoverable Trash folder
  `timetracker-performance-artifacts-20260801.OgtZFF` after their metrics were
  recorded here. No simulator was created; the tested app and all owned Xcode,
  XCTest, Instruments, and analyzer processes were terminated. LaunchServices
  was restored to `/Applications/timetracker.app`, which was relaunched for the
  user.
