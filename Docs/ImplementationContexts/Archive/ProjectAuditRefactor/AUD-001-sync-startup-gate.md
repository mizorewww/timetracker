# AUD-001 — Sync Prompt Startup Gate

Status: complete

## Scope

Make the first application startup read of `SyncConflictService.prompt()` fail
closed. If the authoritative conflict state cannot be read, startup must expose
the diagnostic, remain non-ready, and perform no migration, seeding, refresh,
Pomodoro reconciliation, or system-projection publication. Retrying a later
configuration attempt remains legal after the corrupt file has been
quarantined or the underlying I/O problem is repaired.

Out of scope: changing the conflict file format, CloudKit schema, recovery
choice semantics, later prompt-refresh coalescing, or other audit findings.

## Expected Behavior

1. The initial prompt read occurs before repositories make facade commands
   available and before any write-side startup effect.
2. A valid `nil` prompt continues normal startup.
3. A valid pending prompt enters the existing read-only recovery path.
4. A thrown prompt read records the error, presents the existing recovery
   safety state, leaves startup incomplete, and returns without durable writes.

## Test Record

### Permanent contract: unreadable prompt permits zero startup writes

- Behavior/risk: an unreadable authoritative conflict state must not be
  converted to “no conflict” and must not allow legacy preference migration or
  startup completion.
- Independent oracle: arrange a malformed real state file plus a legacy
  preference sentinel in isolated defaults; after one `configureIfNeeded`, the
  legacy value must remain, no `SyncedPreference` may exist, startup must remain
  incomplete, and persistence safety must be non-ready.
- Boundary: real `TimeTrackerStore.configureIfNeeded` + real
  `SyncConflictService` durable read + in-memory SwiftData container.
- Lifetime: permanent durability/security regression coverage for AD-074.
- Duplication check: prompt unit tests cover throwing decode, while existing
  lifecycle tests cover successful configuration; none proves the absence of
  write-side startup effects when the first prompt read fails.

## Scaffolding

None planned. No `TEST-SCAFFOLD` test is needed.

## Verification

- Red phase: `make TEST_ONLY=timetrackerTests/CoreCloudRecoveryGateTests test`
  failed only the new contract with five assertions against the old
  fail-open behavior.
- Focused green phase: the same command passed 20 tests in the recovery suite.
- `make format`: passed; no source required reformatting.
- `make format-check`: passed, 0/716 files require formatting.
- `make localization-check`: passed, 9/9 resources in parity.
- `make test`: passed, 148 tests in 23 suites with automatic signing.
- The pre-existing SQLite `vnode unlinked while in use` diagnostics tracked as
  AUD-007 remain visible in the preference failure tests; they are outside this
  checkpoint and did not affect the pass result.

## Closeout

- Permanent test retained:
  `CoreCloudRecoveryGateTests.unreadableInitialConflictPromptBlocksEveryStartupWrite`.
- No temporary tests or `TEST-SCAFFOLD` markers were added.
- No simulator, UI runner, trace, network, Keychain, or CloudKit resource was
  created or owned by this checkpoint. The signed macOS test host exited with
  the test command.
