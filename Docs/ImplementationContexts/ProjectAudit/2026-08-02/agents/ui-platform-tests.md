# UI, Platform Surfaces, And Test Architecture Audit

- Assigned scope: SwiftUI application roots, feature composition, `SharedUI`, navigation and presentation ownership, iOS/iPadOS/macOS/watchOS/Widget/Live Activity surfaces, and the quality/architecture of the retained test suite.
- Explicit exclusions: domain persistence/sync/AI implementation except where needed to trace a UI/system-surface caller or test lifecycle; no production or test source changes; no simulator/device batch or new test execution owned by this sub-audit.
- Skills read: repository-local `apple-hig` (including routed foundations, platform, navigation/presentation, Widget, Live Activity, watchOS, menu/window references); repository-local `swiftui-expert-skill` (latest APIs, state, performance, view structure, list/layout, sheet/navigation, macOS scenes/views/window styling); `axiom-testing` (Swift Testing, async, UI testing, XCUITest automation references); `axiom-audit-testing`.
- Project documents read: `AGENTS.md`; `Docs/ImplementationContexts/ProjectAudit/2026-08-02/DocumentationStandard.md`; `Docs/ProjectMap.md`; `Docs/Architecture.md`; `Docs/CodeGuide.md`; `Docs/UI-Design.md`; `Docs/Testing.md`; `Docs/CodeRefactorPlan.md`; relevant accepted decisions in `Docs/AgentDecisions.md`, including AD-008, AD-012, AD-019, AD-020, AD-031, AD-039, AD-040, AD-117, AD-131, AD-134, AD-135, AD-139, and AD-140.
- Files/directories inspected: documentation listed above; all Swift path inventories under `timetracker/App`, `timetracker/Features`, `timetracker/SharedUI`, `timetrackerWatchApp`, `timetrackerWidgetExtension`, `timetrackerLiveActivityExtension`, `SharedLiveActivity`, `timetrackerTests`, and `timetrackerUITests`; complete root-shell/presentation/deep-link files; complete Widget and Live Activity views; Watch store/command/connectivity and principal Watch views; all retained test files by inventory, with focused full reads of the preference failure tests and counterexample ledger persistence test; focused full reads/callers for non-private state owners; complete `AITaskWorkspacePlanGeneratorViews.swift` and its direct production caller.
- Searches or commands used: documentation line counts and chunked reads; accepted-decision heading/keyword searches; `rg --files` Swift/test inventories; mandatory `axiom-audit-testing` import/framework/flakiness/speed/migration/Swift-6/quality/AI-evaluation scans as separate patterns; line-count responsibility scan; SwiftUI state, identity, sheet, platform-layout, task/timer, force-operation, and hack-marker scans; direct caller/test searches; `nl -ba` line refreshes.
- Current status: `complete`.

## Coverage Map

| Area | Status | Notes |
| --- | --- | --- |
| App/root scene and adaptive shell | complete | Width-driven shell, scene store/router lifetimes, deep-link deferral, compact/regular navigation and local/global presentation ownership checked |
| Features and `SharedUI` | complete | Broad static scan plus focused reads of state owners, largest UI concentration, task detail presentation and shared pickers |
| Widget/Live Activity/Watch | complete | Complete Widget/Live Activity view read; Watch store, command transport, status/timer/task UI and identity contract checked |
| Retained unit/UI tests | complete | 147 Swift Testing declarations and four XCTest UI cases inventoried; mandatory audit patterns and focused lifecycle reads completed |
| SQLite test-store cleanup warning | complete | Confirmed against source ownership, observed default-gate diagnostics reported by the primary agent, and the repository's explicit safe counterexample |

## Commands And Searches

- `wc -l` and `sed -n` over required project documents and routed skill references.
- `rg -n` over `Docs/AgentDecisions.md` to identify and read scope-relevant accepted decisions.
- `rg --files -g '*.swift' ...` produced a 716-file scoped Swift inventory and the retained `*Tests.swift`/`*Test.swift`/`*Spec.swift` inventory.
- Separate `rg` scans required by `axiom-audit-testing`: `@testable import`, XCTest/Testing/XCUIApplication, three sleep forms, shared static/class state, UIKit/SwiftUI imports, XCTest migration forms, MainActor/XCTestCase, force casts/tries, setup methods, and all Evaluations-framework patterns.
- SwiftUI/platform scans: non-private `@State`/`@FocusState`, unstable `ForEach` forms, local/global sheets/popovers, platform identity/screen lookups, deprecated/type-erased/tap/geometry/task/timer/force-operation patterns, marker words, file line counts, and direct callers/tests.
- No test or build was launched by this sub-agent. The primary agent's frozen-source `make test` passed 147 cases but repeatedly emitted SQLite `BUG IN CLIENT ... vnode unlinked while in use` diagnostics; that runtime evidence is used only for UI-TEST-001 below.

## UI-TEST-001 — Preference failure tests unlink live SwiftData stores

- Status: confirmed
- Severity: medium
- Category: latent-bug
- Confidence: high
- Evidence: `timetrackerTests/Preferences/PreferenceCommandValidationTests.swift:180`, `timetrackerTests/Preferences/PreferenceCommandValidationTests.swift:201`, `timetrackerTests/Preferences/SyncedPreferenceMigrationFailureTests.swift:14`, `timetrackerTests/Preferences/SyncedPreferenceMigrationFailureTests.swift:19`, `timetrackerTests/Preferences/SyncedPreferenceMigrationFailureTests.swift:39`, `timetrackerTests/Preferences/SyncedPreferenceMigrationFailureTests.swift:57`, `timetrackerTests/Ledger/LedgerPersistenceValidationTests.swift:337`
- Contract: `Docs/Testing.md` requires deterministic, isolated tests and accurate final evidence; SwiftData/SQLite store files must not be removed while a live `ModelContainer`/`ModelContext` still owns them. The repository itself records this exact lifecycle rule in `LedgerPersistenceValidationTests.makeStoreDirectory()`.
- Execution path: the three read-only-store failure cases create a function-local `readOnlyContainer` and `ModelContext`, then register `defer { removeItem(storeDirectory) }`. Swift local lifetime can extend through scope exit, so the defer unlinks the SQLite store and sidecars while descriptors remain open. The primary agent's default `make test` run reached these cases and repeatedly logged `BUG IN CLIENT OF libsqlite3.dylib: vnode unlinked while in use`.
- Impact: the retained default gate passes but emits SQLite client-bug diagnostics; cleanup timing is undefined and can create noisy or flaky test runs, obscure new persistence faults, and leave evidence that is not cleanly deterministic.
- Why this is not intentional: the sibling ledger test deliberately does the opposite, using unique temp paths and allowing OS cleanup because SwiftData may close sidecar descriptors asynchronously (`LedgerPersistenceValidationTests.swift:337-345`). There is no test-isolation benefit to eagerly unlinking a unique temp store before its owners are released.
- Counter-evidence checked: all containing test functions and their helper-created container/context lifetimes; suites are serialized, which prevents concurrent-suite interference but does not shorten object lifetimes; the assertions pass and no production data is at risk; the ledger persistence suite provides an explicit established safeguard.
- Recommendation: apply the existing ledger-test policy to these unique stores (do not eager-remove them), or introduce a scoped helper whose container/context are destroyed before cleanup and verify a final `make test` run has no SQLite client-bug diagnostic.

## UI-PLATFORM-002 — Watch device identity is a shared literal, not the accepted opaque per-device ID

- Status: confirmed
- Severity: low
- Category: latent-bug
- Confidence: high
- Evidence: `timetrackerWatchApp/WatchAppStore.swift:29`, `timetrackerWatchApp/WatchAppStore+Commands.swift:7`, `timetrackerWatchApp/WatchAppStore+Commands.swift:20`, `timetracker/Shared/WatchCommandModels.swift:9`
- Contract: accepted AD-035 requires `watch-<canonical UUID>` stored and reused per platform, with a 42-byte/control-character bound; `DeviceIdentityPolicy` already defines watchOS generation/validation. Watch command DTOs expose and validate a `deviceID`, so the producer must satisfy that contract rather than only the transport's non-empty check.
- Execution path: every Watch start/stop command copies `WatchAppStore.deviceID`, which is unconditionally the literal `"watch"`; retry persists the same DTO. Every physical Watch therefore sends the same value, and the receiver accepts it because `WatchTimerCommand.isStructurallyValid` checks only non-empty/bounded text.
- Impact: the wire field falsely claims device identity and cannot distinguish watches. Current `WatchCommandProcessor` does not propagate the field into the timer mutation, so immediate ledger behavior is not currently corrupted; the latent risk is protocol drift if receipt scoping, audit metadata, or mutation attribution begins relying on the already-public field.
- Why this is not intentional: AD-035 explicitly includes the watch prefix and `DeviceIdentityPlatform.current` has a watchOS case; the literal does not match the documented format. No decision grants Watch a constant-ID exception.
- Counter-evidence checked: full command model validity, codec producer/consumer search, Watch queue/retry lifecycle, `WatchCommandProcessor` and facade caller. Idempotency currently keys on random command UUID and the processor ignores `command.deviceID`, materially limiting current severity. No retained test asserts producer conformance to `DeviceIdentityPolicy`.
- Recommendation: share the existing policy/storage helper with the Watch target and load-or-create a stable `watch-UUID`; validate decoded command IDs against the platform-neutral syntax if the field remains contractual, or remove the unused field through an explicit versioned DTO decision.

## UI-SMELL-003 — AI task-plan UI file owns asynchronous workflow and independently testable destructive review policy

- Status: confirmed
- Severity: medium
- Category: code-smell
- Confidence: high
- Evidence: `timetracker/Features/Tasks/Generation/AITaskWorkspacePlanGeneratorViews.swift:4`, `timetracker/Features/Tasks/Generation/AITaskWorkspacePlanGeneratorViews.swift:328`, `timetracker/Features/Tasks/Generation/AITaskWorkspacePlanGeneratorViews.swift:421`, `timetracker/Features/Tasks/Generation/AITaskWorkspacePlanGeneratorViews.swift:749`, `timetracker/Features/Tasks/Generation/AITaskWorkspacePlanGeneratorViews.swift:975`, `timetracker/Features/Tasks/Generation/AITaskWorkspacePlanGeneratorViews.swift:1020`, `timetracker/Features/Tasks/Generation/AITaskWorkspacePlanGeneratorViews.swift:1213`
- Contract: `Docs/CodeRefactorPlan.md` requires every existing SwiftUI feature file over 250 lines to receive a responsibility review and says views should remain mostly declarative. AD-132/133 make accurate create/update/archive/delete/reuse counts, before/after fields, destructive confirmation, stale preview preservation, cancellation and Apply behavior user-visible safety contracts.
- Execution path: the single 1,402-line file owns sheet/view composition, generation task cancellation and minimum-duration timing, apply/discard state, destructive-operation classification, mutation counts, localized summaries, stable row identities, operation title/context derivation, and every before/after field mapping. A change to an operation case therefore crosses async workflow, safety policy, and rendering in one compilation unit.
- Impact: destructive-confirmation and review-diff regressions are hard to verify independently and can misdescribe what Apply will change. The retained unit/UI suites contain no reference to `AITaskWorkspaceReviewPresentation`, `AITaskWorkspaceOperationPresentation`, `hasDestructiveOperations`, or its field-change mapping, so a realistic new operation/field can compile while omitting review disclosure or confirmation.
- Why this is not intentional: the service/overlay/atomic mutation layers are already separated; no accepted decision says the review policy must remain private inside the view file. File length alone is not the finding—the concrete cost is safety policy coupled to async SwiftUI state and unavailable to narrow behavior tests.
- Counter-evidence checked: complete file, sole direct production presentation caller in `AppPresentationHost`, retained test search, ProjectMap/CodeGuide ownership, AD-132/133, and refactor guardrails. The current exhaustive switches provide compile-time pressure for new enum cases and reduce immediate bug likelihood; live/UI gates described by the ADs provide broader end-to-end evidence when actually run.
- Recommendation: first extract a pure review-presentation/safety policy (counts, destructive classification, identities, context and field diffs) without changing behavior, then retain a small table-driven behavior suite with independent operation fixtures. Split request/review SwiftUI composition separately only after that contract is protected.

## Rejected Candidates / Counter-Evidence

### REJECTED-STATE-PRIVACY — Non-private `@State` and `@FocusState`

- Evidence checked: `SettingsViews.swift:12-17`, `TaskDetailWorkspace.swift:10-20`, `TaskHierarchyPicker.swift:30-31`, every same-type extension and direct caller.
- Rejection reason: repository-local SwiftUI guidance prefers private state, but Swift `private`/`fileprivate` would make these members inaccessible to the intentionally split extensions in other files. The owning view types remain internal, searches found no unrelated mutator, and accepted AD-020 explicitly preserves these semantic file splits. This is a language/access-control tradeoff, not a demonstrated mutable-state escape or bug. Replacing it with a reference state bag solely to satisfy `private` would add indirection without a current correctness gain.

### REJECTED-ASYNC-SLEEP — 10 ms sleep in transport tests

- Evidence checked: `CoreLLMResponseTransportTests.swift:344-356` and async-test policy.
- Rejection reason: this is a bounded poll of the asserted observable condition with a strict two-second deadline, not a fixed delay followed by an assertion; `Docs/Testing.md` explicitly permits that pattern.

### REJECTED-LOCAL-SHEET — Task quantity editor owns a local sheet

- Evidence checked: `TaskDetailContentView.swift:19-20`, `TaskDetailContentView.swift:102-103`, global `AppPresentationRouter` and host.
- Rejection reason: it is a tightly scoped child editor launched only from Task Detail, flushes the autosave boundary first, and no concrete concurrent presentation failure was established statically. The global router's single-sheet policy remains intact for cross-feature/scene routing. Retain as a runtime lead only if SwiftUI reports competing presentation or a deep-link/UI reproduction exists.

### REJECTED-FORCE-UNWRAP — Widget URL/preview UUID constants

- Evidence checked: `WidgetSupport.swift` and `TimeTrackerWidget.swift` force unwraps.
- Rejection reason: inputs are fixed developer-authored URL/UUID literals, not runtime/user data; failure would be an immediate development defect rather than a latent reachable production input crash.

## Open Questions / Runtime Verification

- UI-TEST-001 needs a post-fix full `make test` run with stderr inspection; passing counts alone do not disprove the lifecycle defect.
- UI-PLATFORM-002 needs a watchOS target build after sharing identity policy/storage, because current main-target availability of `DeviceIdentity.swift` was not changed or built in this read-only audit.
- No UI/simulator/device verification was owned by this sub-agent. Widget and Live Activity release status still requires the real-device gates already documented by AD-010 and current project docs.
- No production or test source was modified.
