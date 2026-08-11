# 2026-08-11 Review Refactor — Implementation Memory

Status: Complete

Task source: `Docs/Review-2026-08-11.md`

## Objective

Apply the review's confirmed simplifications without expanding product scope:

- preserve user-visible timer, sync, projection, restore, Watch, Widget, Live Activity, AI, and Apple Health behavior;
- delete verified indirection and dead APIs, single-source duplicated policy, and replace crash-only invariants with ordinary errors;
- simplify current-state system-surface projection after permanent behavior tests exist, while retaining snapshot validation whose proposed reduction would require a new transport envelope;
- move code and completed records to the documented owners without redesigning features.

Explicit non-goals: removing the AI workspace or Apple Health replica, redesigning the UI, changing the SwiftData schema, adding new configuration layers, or retaining compatibility machinery that has no live caller.

## Expected behavior

1. Every committed mutation still converges Widget, Live Activity, Watch, sync-conflict prompt, and in-memory read models from current store facts.
2. Launch, foreground, and Cloud-container replacement still trigger a full current-state reconcile; a failed publish is retried by the next reconcile trigger and is surfaced rather than silently disabling projection.
3. Snapshot import/export keeps format-version, encoded-size, and content-fingerprint protection. Restore remains responsible for domain/reference validation.
4. Existing legacy transport and migration shims remain load-bearing and unchanged.
5. Test-only entry points stay unavailable in Release builds.

## Test record

All tests below are permanent regression coverage unless explicitly marked otherwise. No `TEST-SCAFFOLD` tests are planned.

| Contract / risk | Independent oracle | Boundary | Retention |
| --- | --- | --- | --- |
| Analytics timeline/lane math can regress during the layout-file move | Hand-computed lane positions, widths, and compressed-axis coordinates for small fixtures | Pure `Services/Analytics` API | Permanent product contract |
| Forecast rollups can double-count or omit descendants/segments | Hand-summed task tree and ledger fixtures, including empty and nested cases | Pure forecasting service | Permanent product contract |
| Watch payload compatibility can drift during shared-helper moves | Round-trip equality of canonical DTO fields plus explicit invalid/legacy boundary fixtures | Watch codec transport boundary | Permanent compatibility contract |
| Projection simplification can miss a surface or publish stale facts | In-memory store fixture and recorded surface publications compared with current store state after commit/reconcile | Post-commit projection boundary | Permanent integration contract |
| Snapshot validation can admit an unsupported/oversized/tampered payload | Existing format, byte-cap, fingerprint, and domain fixtures at their owning manifest/restore boundaries | Snapshot manifest and restore boundaries | Permanent durable-data/security contract; implementation unchanged |
| LLM stream validation can crash on malformed provider deltas | Malformed delta/tool fixtures must return the documented error; valid assembled content remains exact | LLM transport/service boundary | Permanent integration contract |
| Pomodoro break completion can resume the wrong timer set when admission policy is unified | Explicit active-segment fixtures compared with the hand-derived exclusive/parallel replacement set | Pomodoro command boundary | Permanent product contract |
| AI workspace canonical re-lookup can crash when an operation invalidates its requested identity | Deliberately unavailable category/task/checklist identities must return the matching typed overlay error | AI overlay boundary | Permanent integration contract |
| AI workspace fingerprint generation can hide encoding failure behind a process trap | JSON round-trip equality plus rejection of a tampered transmitted fingerprint | AI workspace Codable boundary | Permanent compatibility/security contract |
| Apple Health catalog identities can drift while removing string-to-UUID force unwraps | Known role IDs compared with frozen UUID strings | Apple Health catalog model boundary | Permanent durable-data compatibility contract |
| Projection simplification can confuse local commits with remote or surface-only catch-up | Recorded sync/surface publications compared with an explicit request cause and event-to-sink routing table | Projection scheduler/worker boundary | Permanent integration contract |
| UI compact Live Activity checks can silently pass when the surface is absent | Required element query must fail with an actionable assertion when either compact surface is missing | XCUITest system-surface boundary | Permanent product contract |
| Shared presentation helpers can change the distinct main-app, Widget, or Watch clock shapes and accepted color syntax | Frozen locale-specific strings and hand-derived sRGB components for shorthand, canonical, and invalid hex inputs | Pure shared presentation boundary compiled into all three targets | Permanent product contract |
| Retiring uncalled UI fixture branches can break the generic demo launch or the one retained system-surface fixture | Adaptive-shell launch assertions plus the retained long-timer Live Activity launch path | iOS XCUITest launch boundary | Permanent integration contract |

Existing test cleanup is limited to parameterizing duplicate inputs, merging resource-contract ownership, removing constructor-mirroring assertions, and deleting the one redundant static-boolean assertion. It must not reduce durable-data, compatibility, security, or integration coverage.

## Verification and resource ownership

- Run focused suites after each behavior slice, then `make test`, `make localization-check`, and `make format-check`.
- Run affected iOS UI tests through `make test-ui-ios`, which creates, records, shuts down, and deletes an owned simulator.
- Prefer an available macOS VM for macOS UI automation; do not launch intrusive UI automation on the user's active desktop. If no VM path exists, report that gate separately instead of commandeering the desktop.
- Record every created simulator UDID/result bundle, terminate the app and runners, delete owned simulators, and verify no owned Booted device or test process remains.

### macOS UI acceptance checklist

- A Debug `--uitesting` launch opens or adopts one content window after the next main-loop turn, without a timed retry or private selector.
- Optional test width/height is applied before the window is centered and activated.
- A Release build ignores the UI-testing bootstrap path.

The build contracts above are verified in Phase 1E. Interactive macOS automation remains unrun because no configured VM runner is available; the active desktop is deliberately not used for that gate.

## Checkpoints

- Phase 1A: direct repository calls replaced the 14 pass-through use cases; dead timer admission, Watch snapshot, and unused OpenAI stream assembler code were removed. The canonical Pomodoro admission path is covered for exclusive and parallel break resume. `make test` passed 190 tests in 33 suites; localization parity and SwiftFormat lint passed. Deleted sources remain recoverable in `/Users/aac6fef/.Trash/timetracker-phase1a-20260811.vY5Y87/`.
- Phase 1B: Release-only UI-test entry points are excluded, AI workspace encoding and canonical re-lookup failures now propagate ordinary errors, catalog UUIDs are constructed without parsing traps, and the two bare 350 ms delays are named and cancellation-aware. The frozen Apple Health identity test caught and corrected the textual UUID suffixes `10`–`12` as hexadecimal bytes (`0x10`–`0x12`). Focused AI-overlay and catalog tests passed; `make test` passed 190 tests in 33 suites; the signed universal Release macOS build, localization parity, and SwiftFormat lint passed.
- Phase 1C: zero-caller scheduler inspection/manual-retry APIs and their 512-entry receipt ledger were removed while preserving per-sink coalescing and next-relevant-mutation retry. Sync-conflict prompt delivery now shares `StoreMutationBroadcaster`; its synchronous locked file read runs through one structured `@concurrent` helper instead of a dedicated actor. The permanent routing test freezes the event-to-sink table. `make test` passed 191 tests in 34 suites; localization parity and SwiftFormat lint passed. The removed broadcaster source remains recoverable in `/Users/aac6fef/.Trash/timetracker-phase1-broadcast-20260811-1459/`.
- Phase 1D: elapsed-clock string construction and hex normalization/component parsing now have one pure shared implementation compiled into the main app, Widget, and Watch targets; platform-specific presentation shapes and the main app's dynamic color adaptation remain at their existing callers. Focused tests passed 2 tests in 1 suite, `make test` passed 193 tests in 35 suites, and the signed generic iOS build (including embedded Watch and Widget validation) passed.
- Phase 1E: the Debug-only macOS UI-test window bootstrap now uses one next-run-loop handoff and a public fallback window, with no fixed delay or string selector; Release compiles the hook as a no-op. Magic preheat/recurrence timings and the logging bundle fallback are named once. The misleading Widget cache became a stateless projection namespace, zero-caller repository requirements were removed, and four single-conformer protocols were replaced by their concrete stores while preserving startup-time optional configuration. The similarly named refresh entry points were intentionally retained because one runs scene post-refresh effects and Pomodoro reconciliation while recovery refresh must not. `make test` passed 193 tests in 35 suites; signed generic iOS Debug and universal macOS Release builds passed. Three empty directories and the removed protocol source remain recoverable in `/Users/aac6fef/.Trash/timetracker-empty-dirs-20260811.rQYU3N/`.
- Phase 2A: system projections now replay current facts directly from explicit `.localCommit`, `.startupCatchUp`, and `.surfaceCatchUp` requests. Only local/startup work records sync recovery snapshots; startup performs an idempotent full compensation, while foreground/import/resolution and forced Watch cannot impersonate local writes. Per-sink coalescing/retry and one fresh-context DTO materialization per generation remain. The persistent-history driver, impact mapper, four cursor/attempt stores, and parallel reset fence were removed; their two durable tests were retired because AD-142 supersedes that contract, while real locked store-file cleanup remains covered. Removed sources are recoverable in `/Users/aac6fef/.Trash/timetracker-projection-history-20260811.2nbjHj/`. The review's proposed snapshot-preflight collapse was intentionally not applied: `SyncDataSnapshot` has no version/digest envelope, while format/size/SHA ownership already lives in the conflict-state manifest and accepted restore decisions require domain validation; adding an envelope solely to delete those checks would be overdesign. Focused scheduler tests passed 4 tests and Cloud recovery passed 19 tests; `make test` passed 194 tests in 35 suites; signed generic iOS Debug and universal macOS Release builds, SwiftFormat lint, and localization parity passed.
- Phase 3A: the former 69-file `Services/SystemIntegration` concentration is now split by owner into `Sync` (41 files), `SystemProjection` (7), `WatchConnectivity` (5), and the 16-file Apple Health/durable-file/credential/export remainder. The pure 850-line `TimelineChartLayout` moved from `SharedUI` to `Services/Analytics`. Only the Watch target's explicit codec path required a pbxproj edit; filesystem-synchronized sources followed automatically. `make test` passed 194 tests in 35 suites and the signed generic iOS build, including embedded Watch codec validation, passed.
- Phase 3B: `CodeRefactorPlan` now keeps only the active-work rule, live responsibility concentrations, and links to authoritative ownership/testing/workflow documents. Five superseded decisions plus the retired source-scan note moved verbatim to `AgentDecisionsArchive`; the active decision file now states its growth policy and AD-129/AD-130 share the recurrence runtime link. Changed-document links and archive completeness were checked mechanically.
- Phase 3C: the review's exact 122 completed records (8 dated performance memories, 9 ProjectAudit files, 9 ProjectAuditRefactor files, 95 feedback task memories, and 1 design) moved under `ImplementationContexts/Archive` without deletion. Ninety-eight missing English status headers were added, the stale UI-performance header became Complete, and archive-relative references were repaired. The live tree now contains only the recurrence runtime reference and this active memory; all 99 Markdown-local links inside the archive resolve.
- Phase 3D: zero-caller Apple Health, AI, route, analytics-delay, autosave-delay, fixed-clock, density, and historical timeline UI fixtures were removed instead of moved behind another support layer. `SeedData+DemoBuild.swift` shrank from 922 to 268 lines; the generic `--uitesting` launch and the actively called long-timer Live Activity fixture remain. The two removed source files are recoverable in `/Users/aac6fef/.Trash/timetracker-ui-fixtures-20260811.kJpRZu/`. `make test` passed 194 tests in 35 suites, the signed generic iOS build (including Watch, Widget, and Live Activity embedding) passed, SwiftFormat lint and localization parity passed, and the owned iOS simulator batch passed 2 adaptive-shell UI tests. Simulator `CBD264FA-53AA-4D34-8E0D-4B13204B9607` was automatically shut down and deleted; its 1.2 MB result bundle was recorded then moved to `/Users/aac6fef/.Trash/timetracker-ui-test-results-20260811.nAjHKY/`. The remaining multi-source demo selection is intentionally retained: standard UserDefaults launch overrides and Cloud smoke-test restart configuration are active harness contracts, so collapsing them would require redesigning callers rather than deleting dead configuration.

## Closeout

- The permanent behavior, compatibility, security, and integration tests in the record remain. Two persistent-history cursor tests were retired with their superseded implementation contract; no temporary test was promoted. No `TEST-SCAFFOLD` marker remains in production or test targets.
- Final verification passed: `make test` (194 tests / 35 suites), focused projection/Cloud/AI/catalog/presentation suites, `make test-ui-ios` (2 tests), signed generic iOS Debug, signed universal macOS Release, SwiftFormat lint, localization parity, hook verification, changed-link checks, and Git whitespace checks.
- macOS UI automation was not run because no configured VM runner was available; the user's active desktop was not commandeered. Its compile-time Debug/Release contract is covered by the signed builds and the checklist above remains the explicit interactive gate.
- The simulator created by this task was shut down and deleted, its result bundle was moved to the Trash, and no owned Booted simulator, `xcodebuild`, `xctest`, UI runner, or app process remains.
- The snapshot envelope rewrite, facade scheduler extraction, live demo-configuration collapse, and removal of AI or Apple Health were deliberately not performed. They respectively require a new durable format, move coherent behavior without reducing it, replace active harness contracts, or make an owner product decision; doing them in this refactor would exceed the confirmed simplification scope.
