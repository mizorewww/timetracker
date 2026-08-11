# AUD-002/003 Projection Metadata Recovery

Status: complete

## Scope

Close the two durability gaps in post-commit persistent-history metadata:

- A malformed or oversized full-reconciliation attempt must never be treated
  as an absent attempt while an older cursor remains usable.
- A malformed or oversized reset-epoch fence must remain fail-closed during
  ordinary registration, but an explicit physical-store reset must be able to
  recover conservatively instead of permanently disabling projections.

The explicit reset already owns the store-scoped mutation lock and the durable
root lock. Recovery is therefore limited to that boundary: quarantine the bad
epoch, invalidate every lane cursor and attempt, then publish a fresh nonzero
epoch before the physical store is removed.

## Test record

| Contract | Risk protected | Independent oracle | Boundary | Lifetime |
| --- | --- | --- | --- | --- |
| A malformed or oversized attempt forces `interruptedFullReconciliation` even when an older ready cursor exists | A quarantined attempt could be interpreted as absence and allow incremental acknowledgement past unpublished full facts | Establish a real ready baseline, begin a new attempt, replace its sidecar with malformed/oversized bytes, and assert the public cursor load result | `PersistentHistoryLaneCursorStore` plus real `DurableLocalFile` artifacts | Permanent durability regression |
| Explicit reset repairs a malformed or oversized epoch while invalidating every lane; ordinary reads do not repair it | Corrupt epoch metadata could permanently block recovery, or unsafe repair could let a stale coordinator acknowledge a replacement store | Seed cursor/attempt artifacts for all lanes, corrupt the epoch, assert ordinary `currentEpoch` throws, run the public reset fence under the store mutation lock, then assert a nonzero readable epoch, all artifacts absent, and a coordinator registered to epoch 0 reports reset mismatch | `PersistentHistoryProjectionResetFence`, `StoreScopedTimerMutationLock`, and real filesystem artifacts | Permanent durable-data and concurrency regression |

No `TEST-SCAFFOLD` coverage is planned. The tests exercise public/internal
service boundaries and remain as permanent regression contracts.

## Verification

- Red phase: `make TEST_ONLY=timetrackerTests/CoreCloudRecoveryGateTests test`
  built successfully and failed both new contracts across malformed and
  oversized fixtures, recording four issues against the old behavior.
- Focused green phase: the same command passed 22 tests, including all four
  new fixture cases.
- `make format`: passed and formatted the changed Swift source.
- `make format-check`: passed, 0/716 files require formatting.
- `make localization-check`: passed, 9/9 resources in parity.
- `make test`: passed, 150 tests in 23 suites with automatic signing.
- The pre-existing SQLite `vnode unlinked while in use` diagnostics tracked as
  AUD-007 remain visible and are intentionally deferred to that checkpoint.

## Closeout

- Both tests in the record are retained as permanent durable-data and
  concurrency regression contracts; each covers malformed and oversized
  artifacts.
- Corrupt attempts now invalidate the older lane cursor before quarantine, so
  the first load reports an interrupted reconciliation and subsequent loads
  see a missing baseline rather than a ready stale frontier.
- Ordinary reset-epoch reads remain fail-closed. Only explicit reset repairs a
  corrupt fence, under its existing store mutation and durable-root locks, by
  invalidating all lane artifacts and publishing a fresh nonzero epoch.
- No temporary tests or `TEST-SCAFFOLD` markers were added.
- No simulator, UI runner, trace, network, Keychain, or CloudKit resource was
  created or owned. The signed macOS test host exited with each test command.
