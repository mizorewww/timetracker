# High-Density UI Performance — Implementation Memory

Status: verified

Started: 2026-07-29

Branch: `codex/performance-hardening-2026-07-29`

## Objective

Measure and improve display and scrolling performance when Today contains a dense
timeline and every primary page contains many elements. Use deterministic SwiftData
fixtures, scripted iPhone and iPad interaction, and Release Instruments evidence so
data creation is not confused with page rendering.

## Performance context map

- Entry surfaces: compact Today, regular-width Today, Tasks, Inbox, Analytics, and
  their scrolling/navigation transitions.
- State owners: `TimeTrackerStore` owns loaded SwiftData models and value-semantic
  read-model revisions; feature views own only local navigation/filter state.
- Update triggers: store observation, minute clocks on Today visualizations, analytics
  refresh tasks, geometry width changes, search text, and list expansion.
- Persistence boundary: the isolated UI-test demo store is fully seeded before any
  timed interaction begins.
- Main-thread risk: view projection, SwiftUI diffing, Charts mark construction,
  accessibility trees, and non-lazy Today desktop rows.
- Off-main work: analytics visual snapshot projection already resolves through
  `AnalyticsVisualSnapshotTask`.
- Collection boundaries: Today timeline entries/countdowns, task-tree sections and
  row supplements, inbox open/completed projections, and chart points/slices.
- Existing budgets: 2,000-entry analytics snapshots and 5,000-entry timeline layout
  projections; they do not measure mounted view cost or scroll hitches.
- Platform matrix: owned iPhone and iPad simulators; macOS UI automation is excluded
  from the physical host and requires a VM if later needed.
- Cleanup boundary: terminate App/test runners and trace tools, then shut down and
  delete every simulator created for each batch and trash owned transient evidence.

## Deterministic stress matrix

| Surface | Fixture | Interaction |
| --- | --- | --- |
| Today | dense same-day timeline, populated charts, forecasts, quick starts, countdowns | cold navigation, repeated long scroll, return to top |
| Tasks | many categorized roots and children | open, expand, search, scroll |
| Inbox | many open and completed items | open, scroll, expand completed |
| Analytics | dense multi-day ledger across many tasks | open landing, open chart-heavy categories, scroll |
| iPad | same store and routes at regular width | repeat Today and primary-page traversal |

## Acceptance checklist

- [x] A UI-test-only high-density fixture is isolated from production and ordinary
      demo data.
- [x] Scripted iPhone and iPad tests prove each stressed surface remains reachable
      and scrollable with stable identities.
- [x] Release sampling isolates page display/scroll work after seeding. `xctrace`
      could attach to the iOS 27 simulator process but produced an invalid trace
      when stopped, so `/usr/bin/sample` supplied the symbolicated CPU/footprint
      evidence instead.
- [x] The measured regular-width eager-mount bottleneck has an automated
      high-density UI acceptance test and uses lazy row containers.
- [x] The complete signed unit gate and generic iOS/macOS Release builds pass.
- [x] Every completed simulator, process, result bundle, and trace was released after its
      batch.

## Measurements and decision

- Fixture size: 1,200 tasks, 1,580 completed segments, 24 active timers, 400
  inbox items, and 120 countdowns.
- iPhone Release: all four primary surfaces passed. During a 25-second Today
  scroll/idle window the main thread spent 19,982 of 21,978 samples (90.9%) in
  the run-loop wait; no application business function was a CPU hotspot.
  Physical footprint was 321.6 MB, peaking at 334.6 MB.
- iPad Release baseline: Today did not expose its stress marker until 40.5
  seconds. Each swipe took about 7.5 seconds end-to-end because an eager tree of
  600 timeline rows and 120 countdown rows made XCTest/Accessibility traversal
  spend roughly four seconds before each gesture. Tasks, Inbox, and Analytics,
  which already use lazy system lists or bounded chart content, did not show
  that traversal penalty.
- Implementation: regular-width Today timeline and countdown row stacks now use
  `LazyVStack`. Compact Today was already backed by `List`.
- iPad Release after: the stress marker appeared at 21.5 seconds (about 47%
  faster) and swipe cycles fell to about 2.9–3.1 seconds (about 60% faster).
  Accessibility lookup before a gesture fell to about 0.1–0.2 seconds. A
  20-second active scroll sample measured 368.1 MB physical footprint, peaking
  at 387.3 MB; active CPU remained in SwiftUI/AttributeGraph and graphics
  composition rather than application business functions.

The stress fixture intentionally measures first-launch seeding together with
initial presentation, so the launch figures are comparative regression evidence,
not a claim about production cold-launch latency.

## Agent communication

- The primary agent owns all simulator, XCUITest, and Instruments batches.
- No macOS UI automation may run on the physical host.
- Static review may proceed without a simulator; no other agent currently owns a
  runtime resource for this memory.
