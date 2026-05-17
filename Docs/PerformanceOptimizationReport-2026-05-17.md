# Performance Optimization Report - 2026-05-17

Branch: `codex/performance-optimization-20260517`

## Summary

- Scope analyzed: SwiftUI app, macOS/iOS root chrome, Home, Tasks, Task Detail, Inbox, Analytics, Pomodoro, Settings, Sidebar, widget extension, watch app, Live Activity extension, SwiftData repositories, domain stores, analytics/forecast/ledger services, maintenance/demo/sync helpers, and existing tests.
- Stack detected: SwiftUI, SwiftData, WidgetKit, ActivityKit, WatchConnectivity, Swift Testing, Xcode 17 command-line tools.
- Baseline tools used: `complexity-optimizer` static scanner, `rg` source audit, `xcodebuild -list`, `xcodebuild -showdestinations`, `xcrun xctrace list templates`, `xcrun xctrace help record`.
- Xcode performance tooling available: `SwiftUI`, `Time Profiler`, `Animation Hitches`, `App Launch`, `Allocations`, `Data Persistence`, `Swift Concurrency`.
- Simulator target used: iPhone 17 Pro Simulator, iOS 26.5, UDID `93DD2475-B5AD-480B-A6BF-C4AE82F63D03`.
- Patch status: implemented and verified on `codex/performance-optimization-20260517`.

## Analysis Coverage

- [x] App shell and root views: `ContentView`, desktop/iOS roots, phone chrome, settings scene, deep links.
- [x] Home page: metrics/actions, progress, forecast summary, active timers, quick start, timeline rows.
- [x] Tasks page: task tree list, category sections, search, row actions, parent selection.
- [x] Task detail/editor pages: detail analytics, forecast panel, checklist editor, recent records.
- [x] Inbox page: inbox list, capture row, item row, suggestion row/editor.
- [x] Analytics pages: summary list, category detail pages, timeline, hourly activity, overlap, decision/forecast sections.
- [x] Pomodoro pages: setup, active timer, ledger, transition views.
- [x] Settings pages: data, LLM, sync/export/import, Pomodoro plan settings.
- [x] Shared UI: metric cards, action controls, badges, checklist controls, duration labels, task visuals.
- [x] Watch/widget/live activity surfaces: snapshot rendering and command payloads.
- [x] Data layer: SwiftData repositories, persistence fetches, commands, maintenance, sync conflict services.
- [x] Domain logic: `TaskStore`, `LedgerStore`, `RollupStore`, `AnalyticsStore`, `ChecklistStore`, `InboxStore`, refresh planner/coordinator.
- [x] Existing performance tests: `CorePerformanceBudgetTests`, analytics timeline tests, rollup tests.

## Findings And Actions

- [x] P0 Large task trees expand every node on first Tasks-page appearance.
  - Location: `timetracker/Features/Tasks/Management/TasksViews.swift:170`
  - Current pattern: first appearance inserted every task ID into `TaskExpansionState`, forcing very large stress trees to render and diff far more visible rows than the user can inspect immediately.
  - Estimated current complexity: `O(n)` expansion work plus a visible-row/rendering surface that can approach the whole task tree on launch.
  - Recommended change: preserve full expansion for normal-sized trees, but cap initial expansion depth as data size grows. Let users expand deeper branches explicitly.
  - Estimated after: `O(n)` policy pass with a bounded initial visible tree: all nodes for small trees, depth 0-1 for medium trees, and root nodes only for very large trees.
  - Risk: low; this changes initial presentation only for large datasets and keeps all manual expand/collapse behavior intact.
  - Change made: added `TaskInitialExpansionPolicy` and `TaskExpansionState.replace(with:)`; stress unit coverage verifies large trees expand roots only.
  - Verification: focused stress unit tests plus compact and large stress UI runner profiles passed.

- [x] P0 Analytics snapshot repeatedly scans all historical segments for current-period rhythm, quality, root breakdown, and category breakdown.
  - Location: `timetracker/Stores/Domains/AnalyticsStore+SnapshotBuilding.swift:85`
  - Current pattern: compute `rangeSegments`, but several current-period metrics are rebuilt from `allSegments`.
  - Estimated current complexity: roughly `O(k*n + grouped sorts)`, where `n` is all history and `k` is the number of derived analytics passes.
  - Recommended change: pass `rangeSegments` to current-period analytics and reserve `allSegments` for comparison with the previous period.
  - Estimated after: `O(n)` once to filter plus `O(k*r)`, where `r` is the selected period.
  - Risk: low; the same interval filter is already used.
  - Change made: current-period rhythm, quality, root breakdown, and category breakdown now consume `rangeSegments`; comparison logic still receives `allSegments`.
  - Verification: analytics tests and performance budget passed.

- [x] P0 Dense overlap analytics scans every active overlap candidate for each event interval.
  - Location: `timetracker/Stores/Domains/AnalyticsStore+Overlap.swift:54`
  - Current pattern: when more than one segment is active, each event interval walks `active.values` to sort/select the first two visible overlap titles.
  - Estimated current complexity: worst-case `O(e*a)` after event sorting, where `e` is start/end events and `a` is concurrently active segments.
  - Recommended change: keep active segment IDs in a set and maintain a min-heap ordered by the original display precedence, lazily dropping ended segments from the heap.
  - Estimated after: `O(e log a)` after event sorting, with constant-time active membership checks.
  - Risk: medium; overlap ordering and equal-start tie breakers are user-visible in analytics.
  - Change made: overlap analysis now uses `activeIDs` plus `OverlapMinHeap`, preserving start/title/id ordering while avoiding repeated full active scans.
  - Verification: iOS Simulator dense overlap performance budget improved from 2.985-3.008s before this optimization to 0.479-0.534s after it; analytics timeline overlap behavior tests passed.

- [x] P0 Hourly analytics scans the segment list once per hour.
  - Location: `timetracker/Services/Analytics/HourTaskActivityService.swift:17`, `timetracker/Services/Analytics/AnalyticsEngine.swift:35`
  - Current pattern: `(0..<24).map` calls a full segment reduction/filter for each hour.
  - Estimated current complexity: `O(24*n + per-hour merge/sort)`.
  - Recommended change: clip each segment to the day once, distribute seconds into touched hour buckets, and maintain wall-clock intervals per bucket.
  - Estimated after: `O(n*h + 24*m log m)`, where `h` is hours touched by each segment, usually 1-2.
  - Risk: medium; must preserve overlapping wall-clock behavior and cross-hour clipping.
  - Change made: `AnalyticsEngine` and `HourTaskActivityService` now clip each segment to the day once and distribute work into hourly buckets.
  - Verification: existing hourly tests and dense analytics performance budget passed.

- [x] P0 Task detail child breakdown rescans all segments for each child branch.
  - Location: `timetracker/Stores/Domains/AnalyticsStore+DecisionSupport.swift:533`
  - Current pattern: for each immediate child, recursively rebuild descendant IDs and call `boundedSegments` over every segment.
  - Estimated current complexity: `O(c*t + c*s)`, where `c` is immediate children, `t` tasks, `s` segments.
  - Recommended change: bound once, group by task ID once, reuse subtree ID cache per child.
  - Estimated after: `O(t + s + c log c)`.
  - Risk: medium; must preserve direct-vs-descendant contribution labels and ordering.
  - Change made: task detail analytics bounds once, groups bounded segments by task ID, and caches child subtree IDs.
  - Verification: task analytics tests and performance budget passed.

- [x] P1 Timeline lane assignment scans lanes linearly per visible segment.
  - Location: `timetracker/Services/Analytics/TimelineLayoutEngine.swift:36`
  - Current pattern: `firstIndex` over `laneEnds` for every item.
  - Estimated current complexity: worst-case `O(n*l)`, up to `O(n^2)` when many lanes overlap.
  - Recommended change: use a small min-heap for ending lanes plus a min-heap for available lane indexes, preserving the lowest available lane behavior.
  - Estimated after: `O(n log l)`.
  - Risk: medium; lane ordering is user-visible in timeline layout.
  - Change made: lane release and reuse now use min-heaps while preserving lowest available lane selection.
  - Verification: timeline layout tests and large-row performance budget passed.

- [x] P1 SwiftUI row date formatting creates `DateFormatter` during body evaluation.
  - Location: `HomeTimelineRows.swift:140`, `TaskDetailView.swift:399`, `AnalyticsTimelineGridViews.swift:137`, `AnalyticsTimelineRows.swift:85`, `AnalyticsRowsViews.swift:149`, `AnalyticsPeriodSelectionViews.swift:87`
  - Current pattern: multiple row/list/timeline render paths allocate `DateFormatter`.
  - Estimated current complexity: still `O(rows)`, but with expensive constant-factor allocation on render.
  - Recommended change: replace fixed `HH:mm` and `MM/dd HH:mm` formatting with lightweight calendar component helpers.
  - Estimated after: `O(rows)` with lower allocation churn.
  - Risk: low; output pattern remains fixed-width.
  - Change made: hot row/timeline formatters now use `TimeDisplayFormatter` calendar component helpers; month selector uses `Date.FormatStyle`.
  - Verification: build passed; `rg "DateFormatter\\(" timetracker` returns no direct formatter allocations in app code.

- [x] P1 Task scoped refresh finds descendant tasks by recursively filtering the full task array.
  - Location: `timetracker/Stores/Domains/TaskStore.swift:31`
  - Current pattern: each recursive step performs `tasks.filter`.
  - Estimated current complexity: `O(d*n)` for a deleted subtree.
  - Recommended change: group existing tasks by parent once in `refreshTaskScoped`.
  - Estimated after: `O(n+d)`.
  - Risk: low; subtree removal behavior remains the same.
  - Change made: `refreshTaskScoped` builds a parent-to-children index once and reuses it during subtree traversal.
  - Verification: `CoreTaskStoreTests` passed.

- [x] P2 Timeline/home sections repeatedly ask for `.last` inside row builders.
  - Location: `HomeTimelineViews.swift:14`, `HomeTimelineViews.swift:39`, `TaskDetailView.swift:243`, `TaskDetailView.swift:357`, `AnalyticsTimelineViews.swift:44`
  - Current pattern: repeated collection property lookup inside `ForEach`.
  - Estimated current complexity: `O(rows)` with small constant cost.
  - Recommended change: where touched for other work, hoist last IDs outside row builders.
  - Estimated after: `O(rows)` with lower view-builder churn.
  - Risk: low.
  - Change made: touched row builders now hoist last IDs outside `ForEach`.
  - Verification: build passed.

- [x] P2 Scanner warnings in SwiftUI root/chrome files are mostly result-builder false positives.
  - Location: `PhoneChromeViews.swift`, `DesktopRootViews.swift`, `ContentView.swift`, `iOSRootViews.swift`
  - Current pattern: `ForEach`, `List`, `GeometryReader`, and `ViewBuilder` closures are reported as nested loops.
  - Decision: no broad rewrite; actual scroll observer and phone chrome state mutations are constant-time and guarded by quantized scroll state.
  - Risk: low.
  - Verification: code inspection.

- [x] P2 SwiftData fetch loops in app/demo/maintenance are cold paths or explicit bulk fetch/delete operations.
  - Location: `SeedData+Cleanup.swift`, `MaintenanceServices.swift`, `CloudSyncSmokeTestRunner.swift`
  - Current pattern: static scanner flags looped deletes/fetch-adjacent code.
  - Decision: no hot-path optimization in this pass; these are user-triggered maintenance/demo paths.
  - Risk: low.
  - Verification: code inspection and lifecycle tests if touched later.

- [x] P2 Startup/deep-link scanner warnings are small bounded parsing paths.
  - Location: `AppBuildInfo.swift`, `AppDeepLinkRouter.swift`
  - Current pattern: static scanner sees SwiftUI fallback builder and URL/query parsing helpers as nested callback/loop candidates.
  - Decision: no optimization; app icon fallback construction and `URLComponents.queryItems.first(where:)` run on tiny bounded inputs and are not measured hotspots.
  - Risk: low.
  - Verification: code inspection.

## Xcode Performance Tooling

- [x] Built baseline macOS Release app with `xcodebuild`.
- [x] Booted iPhone 17 Pro Simulator and ran focused simulator performance tests.
- [x] Built iOS Simulator Release app with `xcodebuild`.
- [x] Installed and launched the Release simulator app with `xcrun simctl`.
- [x] Confirmed available Instruments templates with `xcrun xctrace list templates`, including `SwiftUI`, `Time Profiler`, `Animation Hitches`, `App Launch`, `Allocations`, `Data Persistence`, and `Swift Concurrency`.
- [x] Ran App Launch recording attempts with `xcrun xctrace record --template "App Launch"`.
- [x] Ran SwiftUI recording attempts with `xcrun xctrace record --template "SwiftUI"`.
- [x] Ran simulator `xcrun xctrace` attempts for App Launch, SwiftUI, and Time Profiler.
- [x] Re-ran focused performance/unit tests after implementation.
- [x] Re-ran macOS Release build after implementation.

Trace note: this machine already had another signed `timetracker` instance running from `build/DerivedData-FigmaReverse`. LaunchServices redirected normal same-bundle-id recording to that debug app. A temporary copied Release app with a unique bundle id allowed `xctrace` to target `/tmp/timetracker-perf-profile.app`, but it exited with `SIGTRAP` because the changed signing/bundle identity broke the app's launch assumptions. The trace artifacts are retained at `/tmp/timetracker-app-launch-after.trace` and `/tmp/timetracker-swiftui-after.trace`, but they should be treated as tooling validation and environment diagnostics, not as comparable runtime measurements for this patch.

Simulator trace note: the Release simulator app launched successfully with bundle id `me.mezorewww.timetracker`, and simulator logs confirmed the app stayed active. `xcrun xctrace record --template "SwiftUI"` reported that the SwiftUI and Hitches instruments are not supported on Simulator in this Xcode/runtime combination. Simulator App Launch and Time Profiler CLI recordings hung during collection/saving and were killed, leaving no reliable comparable trace export. The usable simulator measurements for this pass are therefore the focused XCTest performance budgets plus Release build/install/launch validation. For SwiftUI/Hitches trace data, use a physical iPhone target or the Instruments GUI if simulator recording is required.

## Verification Results

- [x] Baseline focused performance budget: `xcodebuild test -project timetracker.xcodeproj -scheme timetracker -destination 'platform=macOS' -only-testing:timetrackerTests/CorePerformanceBudgetTests` passed before changes.
- [x] Post-change focused tests: `CorePerformanceBudgetTests`, `AnalyticsTimelineTests`, and `CoreTaskStoreTests` passed.
- [x] Post-change Release build: `xcodebuild build -project timetracker.xcodeproj -scheme timetracker -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/timetracker-perf-derived-after` passed.
- [x] Simulator focused tests before overlap heap optimization: `CorePerformanceBudgetTests`, `AnalyticsTimelineTests`, and `CoreTaskStoreTests` passed on iPhone 17 Pro Simulator; dense overlap budget measured 2.985-3.008s.
- [x] Simulator focused tests after overlap heap optimization: `CorePerformanceBudgetTests` and `AnalyticsTimelineTests` passed on iPhone 17 Pro Simulator; dense overlap budget measured 0.479-0.534s.
- [x] Simulator Release build after overlap heap optimization: `xcodebuild build -project timetracker.xcodeproj -scheme timetracker -configuration Release -destination 'platform=iOS Simulator,id=93DD2475-B5AD-480B-A6BF-C4AE82F63D03' -derivedDataPath /tmp/timetracker-sim-perf-derived-after` passed.
- [x] macOS focused tests after overlap heap optimization: `CorePerformanceBudgetTests` and `AnalyticsTimelineTests` passed; dense overlap budget measured 0.522-0.527s.
- [x] Static formatter audit: no direct `DateFormatter(` allocations remain under `timetracker`.
- [x] Whitespace audit: `git diff --check` passed.
- [x] Complexity scanner re-run: remaining high-severity items are dominated by SwiftUI result-builder false positives and cold maintenance/demo paths already documented above.

## Completion Log

- [x] Created branch `codex/performance-optimization-20260517`.
- [x] Ran repository complexity scan.
- [x] Audited SwiftUI page and domain-service hot paths.
- [x] Implemented P0/P1 optimizations.
- [x] Ran simulator performance pass and identified dense overlap analytics as the remaining measured hotspot.
- [x] Implemented dense overlap heap optimization.
- [x] Re-ran simulator performance tests and Release simulator build.
- [x] Verified tests/build/Xcode trace attempts.
- [x] Marked all findings complete or explicitly verified-no-change.
