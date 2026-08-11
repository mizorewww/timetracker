# AUD-007 SwiftData Test Store Lifetime

Status: complete

## Scope

Make disk-backed SwiftData tests stop unlinking unique SQLite stores while
their `ModelContainer`, `ModelContext`, or asynchronous SQLite teardown may
still hold sidecar descriptors. The original finding covered three preference
failure tests; the first full verification exposed the same root cause in the
V9 migration fixture, so the fix also normalizes the active schema fixtures,
Apple Health replica fixture, and local-fallback fixture. Production
persistence behavior is unchanged.

The repository's established ledger-test policy is the oracle: unique stores
that exercise SwiftData failure paths remain in the sandbox temporary directory
for operating-system cleanup because SwiftData can close sidecar descriptors
asynchronously.

## Test record

| Contract | Risk protected | Independent oracle | Boundary | Lifetime |
| --- | --- | --- | --- | --- |
| Standalone preference mutation rolls back after a read-only save failure | Test cleanup must not hide or add a persistence failure after assertions finish | Existing rollback assertions plus absence of SQLite `vnode unlinked while in use` diagnostics | `PreferenceCommandHandler` with a disk-backed read-only store | Permanent product regression; unchanged |
| Legacy and sensitive preference migrations roll back after a read-only save failure | Migration failure evidence must remain deterministic and descriptor-safe | Existing migration/credential/defaults assertions plus absence of SQLite client-bug diagnostics | `SyncedPreferenceService` migration boundaries with disk-backed stores | Permanent compatibility/security regressions; unchanged |
| Disk-backed schema and recovery fixtures preserve their existing migration/recovery assertions without unlinking live SQLite sidecars | A passing compatibility suite can still violate SQLite ownership during deferred cleanup | Existing fixture assertions plus a full-suite stderr scan for SQLite client-bug diagnostics | Active V8/V9/V11/V12, Apple Health replica, and local-fallback disk stores | Permanent compatibility/recovery regressions; unchanged |

No new test declaration is needed: the defect is the fixture lifecycle around
three existing permanent tests, and stderr inspection is its independent
resource-safety oracle. No temporary test scaffolding is planned.

## Verification and closeout

- `PreferenceCommandValidationTests`: 9/9 passed; captured output contained no
  SQLite client-bug diagnostic.
- `SyncedPreferenceMigrationFailureTests`: 2/2 passed; captured output contained
  no SQLite client-bug diagnostic.
- The first full run correctly caught the same lifecycle defect in the V9
  fixture, expanding the same-root cleanup audit before closeout.
- Final `make test`: 154 tests in 23 suites passed; a captured-output scan found
  no `BUG IN CLIENT`, `vnode unlinked while in use`, or `database integrity
  compromised` diagnostic.
- `make format`: 716 Swift files formatted; the final source state is clean.
- Existing permanent product tests and their assertions were retained; only
  fixture cleanup ownership changed. No test scaffolding was added.
- No owned simulator, `xcodebuild`, `xctest`, or trace process remains.
