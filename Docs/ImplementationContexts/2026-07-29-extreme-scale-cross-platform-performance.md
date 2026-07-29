# Extreme-Scale Cross-Platform Performance — Implementation Memory

Status: complete

Started: 2026-07-29

Branch: `codex/performance-hardening-2026-07-29`

## Objective

Continue the performance-hardening work with SwiftData fixtures at the product's
untrusted snapshot scale. Identify normal user actions whose work grows with unrelated
records, add failing large-data budgets, and move shared command paths to bounded
queries without changing lifecycle, LWW, archive, recurrence, or sync-only semantics.

## Scope

- Start with timer admission because the same store-scoped command is used by the
  iPhone, iPad, and macOS app, Watch commands, Widget and Live Activity deep links,
  Shortcuts/App Intents, and other system actions.
- Stress one timer start with at least 100,000 unrelated persisted rows across Task and
  preference data, in addition to the existing 50,000-segment budgets.
- Preserve canonical duplicate resolution, archived/deleted ancestor rejection,
  Apple Health sync-only ancestry, recurrence-template claims, and the exact synced
  `allowParallelTimers` preference winner.
- Add behavior/performance tests before production changes.
- Verify shared code through signed macOS unit tests plus generic iOS (including Watch,
  Widget, and Live Activity) and macOS builds.
- Do not perform macOS UI automation on the physical host. If UI automation becomes
  necessary, use a macOS virtual machine.
- After every test/profile batch, release and audit the owned App, runner, build,
  simulator, trace, and temporary artifacts.

## Initial evidence

- Existing `CorePerformanceBudgetTests` use 50,000 `TimeSegment` rows for incremental
  rollup, recent-index mutation, recurrence startup, Pomodoro cancellation, and rapid
  restart. Snapshot preflight accepts at most 100,000 records per table and 250,000
  records total, but no normal timer-start budget currently exercises a six-figure
  store.
- `StoreScopedTimerCommandCoordinator.start` loads every visible Task, recurrence rule,
  and occurrence to decide whether one target Task can receive work.
- `TimerAdmissionPreferenceResolver` loads every synced preference even though timer
  admission needs only `allowParallelTimers`.
- These reads occur inside the serialized store mutation boundary, so unrelated
  history increases user-visible command latency and holds the writer lock longer on
  every main-app and system-action entry point.

## Batch log

- 2026-07-29: `extreme-timer-admission-red-20260729` is owned by the primary
  agent. It runs the signed host-macOS `CorePerformanceBudgetTests` only. The new
  fixture persists one target Task plus 50,000 unrelated Tasks and 50,000 unrelated
  synced-preference rows, then times one ordinary store-scoped timer start against a
  250 ms regression alarm. It performs no UI automation, simulator launch, macOS
  virtual-machine work, or Instruments recording. Cleanup requires the test host,
  `xcodebuild`, and `xctest` to exit and zero Booted simulators.
- 2026-07-29: The red implementation spent 7.315866947 seconds inside one timer
  command and failed the 250 ms alarm. The other 14 performance budgets passed.
  Result: `Test-timetracker-2026.07.29_15-23-15-+0800.xcresult`.
- 2026-07-29: After replacing broad task/recurrence/preference reads with scoped
  predicates, all 15 performance budgets passed in 23.925 seconds and the six-figure
  command passed the 250 ms alarm. Result:
  `Test-timetracker-2026.07.29_15-26-22-+0800.xcresult`.
- 2026-07-29: Targeted recurrence/direct-work semantics passed 5/5 and timer system
  action/preference semantics passed 23/23. Each batch ended with no owned test/build
  process and zero Booted simulators.
- 2026-07-29: Frozen-source `make format-check` passed, followed by the complete signed
  macOS unit gate: 1,582 tests in 176 suites passed in 69.549 seconds. Result:
  `Test-timetracker-2026.07.29_15-32-44-+0800.xcresult`.
- 2026-07-29: Signed `Release` generic macOS and generic iOS builds passed. The iOS
  product embedded and validated Watch, Widget, and Live Activity targets. No UI
  automation was needed or run on the physical macOS host.
- 2026-07-29: Every test and build batch ended with no owned `xcodebuild`, `xctest`,
  app, or runner process and zero Booted simulators.

## Acceptance

- [x] A six-figure persisted-row timer-start fixture fails against the current broad
      fetch implementation for the intended reason.
- [x] The same fixture passes a bounded command-time alarm after implementation.
- [x] Targeted semantic tests cover duplicate, ancestor, sync-only, recurrence, and
      preference-winner behavior.
- [x] Existing performance budgets and the complete signed unit suite pass.
- [x] Signed macOS and generic iOS/Watch/Widget/Live Activity builds pass.
- [x] Every owned runtime resource is audited empty.
- [x] Current architecture, code guide, project map, and testing documentation describe
      the bounded admission boundary.
