# 2026-08-11 Review Refactor — Implementation Memory

Status: active

Task source: `Docs/Review-2026-08-11.md`

## Objective

Apply the review's confirmed simplifications without expanding product scope:

- preserve user-visible timer, sync, projection, restore, Watch, Widget, Live Activity, AI, and Apple Health behavior;
- delete verified indirection and dead APIs, single-source duplicated policy, and replace crash-only invariants with ordinary errors;
- simplify current-state system-surface projection and snapshot preflight only after permanent behavior tests exist;
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
| Snapshot-preflight reduction can admit an unsupported/oversized/tampered snapshot | Explicit version, byte-cap, and fingerprint fixtures at each boundary | Snapshot preflight boundary | Permanent durable-data/security contract |
| LLM stream validation can crash on malformed provider deltas | Malformed delta/tool fixtures must return the documented error; valid assembled content remains exact | LLM transport/service boundary | Permanent integration contract |
| UI compact Live Activity checks can silently pass when the surface is absent | Required element query must fail with an actionable assertion when either compact surface is missing | XCUITest system-surface boundary | Permanent product contract |

Existing test cleanup is limited to parameterizing duplicate inputs, merging resource-contract ownership, removing constructor-mirroring assertions, and deleting the one redundant static-boolean assertion. It must not reduce durable-data, compatibility, security, or integration coverage.

## Verification and resource ownership

- Run focused suites after each behavior slice, then `make test`, `make localization-check`, and `make format-check`.
- Run affected iOS UI tests through `make test-ui-ios`, which creates, records, shuts down, and deletes an owned simulator.
- Prefer an available macOS VM for macOS UI automation; do not launch intrusive UI automation on the user's active desktop. If no VM path exists, report that gate separately instead of commandeering the desktop.
- Record every created simulator UDID/result bundle, terminate the app and runners, delete owned simulators, and verify no owned Booted device or test process remains.

## Closeout checklist

- Reconcile this test record with retained tests and verification evidence.
- Confirm no `TEST-SCAFFOLD` marker remains in the changed scope.
- Archive completed implementation memories and decision history according to the updated active-doc policy.
- Mark this memory complete only after resource cleanup and final verification.
