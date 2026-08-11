# Full Project Audit Report — 2026-08-02

Status: complete

## Executive Summary

The audit confirmed 10 findings: 1 high, 8 medium, and 1 low. No critical issue, confirmed memory leak, schema-chain break, credential disclosure, insecure HTTP path, or reachable production crash was found. The strongest defect is a fail-open startup read at the sync-conflict boundary. Two additional durability defects can prevent conservative projection recovery when small sidecar files are corrupt.

Most of the project's complexity is justified. Versioned SwiftData schemas, durable-file atomic publication, cross-process locking, snapshot validation, bounded queues, full-workspace AI CAS, and platform projections protect documented sync, migration, or system-surface contracts. The only confirmed over-engineering is a replaced AI planning stack that remains compiled and callable with no production caller.

## Confirmed Findings

### AUD-001 — Startup can write while authoritative sync safety is unknown (high)

`TimeTrackerStore.configureIfNeeded` uses `try? syncConflictService.prompt()`. A corrupt, oversized, or unreadable authoritative conflict state becomes `nil`, after which preference migration, legacy migration, seeding, refresh, and reconciliation may run before the later bootstrap retry. This directly violates AD-074's throwing/fail-closed boundary and the read-only recovery barrier.

Smallest safe direction: make the initial prompt a throwing startup gate and prove with a lifecycle test that an unreadable prompt causes zero write-side startup effects.

### AUD-002 — Corrupt reconciliation attempt can skip required full recovery (medium)

The durable full-reconciliation attempt is the crash marker for at-least-once recovery. Its loader quarantines malformed/oversized data and returns `nil`; the lane can then accept its older cursor and continue incrementally. Treat `corrupt` separately from `missing` and force full reconciliation after quarantine.

### AUD-003 — Corrupt reset epoch has no conservative self-healing path (medium)

Reset-epoch decode failure blocks coordinator registration, all cursor epoch checks, and `advanceForStoreReset` itself. Failing closed is correct, but there is no locked recovery transition. Recovery should quarantine the fence, invalidate every lane cursor/attempt, publish a new nonzero epoch, and force full reconciliation without ever substituting epoch zero.

### AUD-004 — Recurrence lifecycle materializes closed history (medium)

Every fresh recurrence state fetches all quantity entries and all Pomodoro runs, then filters active Pomodoro work in memory. This runs on `@MainActor` inside serialized store work and contradicts the documented active-row/canonical-ID bounded-query contract. Convert the relevant history discovery to predicate-first, canonical-ID resolution and verify with a seeded Release trace.

### AUD-005 — Checklist reorder repeats scoped work as a full-table fetch (medium)

The coordinator fetches and CAS-validates exactly one task's checklist rows; the handler then runs an unpredicated fetch of all checklist rows and filters back to that task. Reuse the validated set or predicate the handler query while retaining stale-baseline semantics.

### AUD-006 — File-lock timeout is not monotonic (medium)

Both cross-process lock implementations promise a five-second bounded wait but compare `Date()` to a wall-clock deadline. Clock rollback can extend the wait and a forward correction can terminate early. Use `ContinuousClock` or `CLOCK_MONOTONIC`; share deadline/backoff logic while preserving the distinct `flock` and `lockf` error handling.

### AUD-007 — Tests unlink live SQLite stores (medium, test-only)

Three preference failure tests defer directory deletion while local `ModelContainer`/`ModelContext` owners can remain alive. The green default test run emitted repeated SQLite `vnode unlinked while in use` client-bug diagnostics. Use the repository's existing unique-temp-store policy or ensure owners are destroyed before cleanup, then require a warning-free test run.

### AUD-008 — Obsolete AI planning stack remains shipping surface (medium)

The replaced `LLMTaskPlanService`, old command coordinator, and `saveAITaskPlan` facade retain about 1,125 lines of callable production code with no production construction/caller. Extract the few still-shared errors/constants and compatibility DTOs, then delete the obsolete network and mutation entry points. This reduces policy drift without weakening compatibility evidence.

### AUD-009 — AI review safety policy is coupled to a 1,402-line SwiftUI workflow (medium)

One file owns generation/cancellation/apply state plus destructive classification, counts, row identity, summaries, and before/after field mapping. The pure review policy has no retained test reference. Extract the presentation/safety policy first and protect it with table-driven behavior fixtures; split UI composition only afterward.

### AUD-010 — Watch identity is a shared literal (low)

Watch command DTOs always carry `"watch"`, contrary to AD-035's stable per-device `watch-UUID`. The receiver currently ignores this field and idempotency uses command UUIDs, limiting present impact. Either produce a persisted policy-compliant ID or explicitly version/remove the unused field.

## Runtime-Gated Lead

AI workspace Apply captures, canonicalizes, fingerprints, validates, and mutates the complete uncapped workspace synchronously on `@MainActor` under the writer boundary. That is a credible jank risk, but complete atomic CAS is an accepted product requirement. It remains unconfirmed until a seeded Release trace measures main-thread responsiveness and transaction duration; truncating the workspace is not an acceptable fix.

## Important Rejected Leads

- V1 through V14 schemas and adjacent migration stages are contiguous; no registration or destructive-migration gap was found.
- Keychain storage, ephemeral HTTPS transport, response caps, redirects, and secret logging checks found no credential/privacy defect.
- Durable draft/sidecar files use bounded reads, atomic same-directory publish, protection, backup exclusion, containment, and quarantine safeguards.
- `PreferenceJSON`'s compatibility `"null"` fallback cannot cross the checked durable command boundary for current preference types.
- Non-private SwiftUI state is required by intentional cross-file extensions and has no unrelated mutator; wrapping it merely to gain `private` would add indirection.
- Detached analytics receives immutable `Sendable` snapshots; inspected stored tasks and observer tokens have cancellation/removal ownership. No static memory leak was confirmed.
- Full-table work is not inherently defective here: complete AI CAS and tombstone/logical-identity reconstruction are documented safeguards. Only paths with a narrower authoritative contract were reported.

## Verification And Limits

- `make format-check`: passed, 0/716 files require formatting.
- `make localization-check`: passed for all 9 localized resources.
- `make test`: passed, 147 tests in 23 suites; SQLite lifecycle diagnostics remain AUD-007.
- `make build-ios`: passed with automatic signing and the configured development team/profile.
- Production and test sources were not changed. Only this audit context directory was added.
- This was a broad static/read-only audit plus host tests and builds, not an exhaustive formal proof. Real-device Widget/Watch/Live Activity gates, performance traces, CloudKit fault injection, and post-fix verification remain separate checkpoints.

## Recommended Order

1. Fix AUD-001 first and add the zero-startup-write failure contract.
2. Repair AUD-002 and AUD-003 together as one projection-metadata corruption hardening change.
3. Remove the bounded-query regressions AUD-004/AUD-005 and capture seeded Release evidence.
4. Replace wall-clock lock deadlines (AUD-006) and clean the test-store lifecycle (AUD-007).
5. Refactor/delete AI duplicate and presentation surfaces (AUD-008/AUD-009) behind retained contracts.
6. Correct or version the Watch identity field (AUD-010), then run Watch/device gates.
