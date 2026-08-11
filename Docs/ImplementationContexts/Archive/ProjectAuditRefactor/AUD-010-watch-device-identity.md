# AUD-010 Watch Device Identity

Status: complete

## Scope

- Replace the shared command producer literal `"watch"` with the accepted
  AD-035 identity format `watch-<canonical uppercase UUID>`.
- Persist the opaque identifier in the Watch app's own `UserDefaults` so it is
  stable across launches, while malformed, legacy, cross-platform, controlled,
  or oversized values are replaced.
- Share the existing identity policy/storage implementation with the Watch
  target instead of introducing a second validator.
- Preserve command UUID idempotency, durable `transferUserInfo` delivery,
  direct-message acceleration, restored legacy commands, queue caps, and all
  existing UI behavior. Do not derive identity from hardware, account, host, or
  connectivity state.

The `axiom-watchos` connectivity guidance confirms that queued command delivery
must remain durable and independently idempotent; `deviceID` is metadata, not a
delivery guarantee or authentication credential.

## Test record

| Contract | Risk protected | Independent oracle | Boundary | Lifetime |
| --- | --- | --- | --- | --- |
| Watch identity uses the exact canonical `watch-UUID` value and is stable on the second load | Every command can keep emitting a shared literal or rotate identity on launch | Fixed UUID factory plus two loads from one isolated defaults suite | Shared `WatchDeviceIdentity` policy/storage adapter | Permanent protocol contract |
| Legacy/shared, cross-platform, malformed, controlled, oversized, and noncanonical persisted values are replaced and written back | Unsafe or identifying legacy metadata can continue propagating | Table of invalid strings and fixed replacement UUIDs | Identity validation/storage boundary | Permanent privacy/compatibility contract |
| Independent Watch defaults stores obtain different opaque identifiers | Two Watch installations can collapse to one producer identity | Two isolated suites with distinct fixed UUID factories | Persisted identity boundary | Permanent multi-device contract |

Tests use injected defaults and UUID factories; they do not inspect source text.
No test scaffolding is planned.

## Implementation outcome

- Moved the accepted identity policy/storage implementation from the
  Ledger-only folder to `timetracker/Shared/DeviceIdentity.swift` and compiled
  that exact file into both the main App and Watch targets.
- Added `WatchDeviceIdentity.loadOrCreate(defaults:makeUUID:)`, which pins the
  platform to `.watch` while retaining injected storage and randomness for
  deterministic tests.
- `WatchAppStore` now resolves its immutable producer identity from its own
  injected defaults during initialization. New commands carry a stable
  `watch-<canonical UUID>`; a legacy `"watch"` value is rejected and replaced.
- Existing restored commands are intentionally left untouched, and retry keeps
  their command UUID and payload. Durable `transferUserInfo`, opportunistic
  direct-message acceleration, timeout, caps, and receiver behavior did not
  change.

## Verification and closeout

- Red seam: the new tests initially failed to compile with five
  `Cannot find 'WatchDeviceIdentity' in scope` errors.
- Focused gate: 3 tests passed, including six table-driven invalid persisted
  values; the same build compiled and signed `timetrackerWatchApp` with the
  shared identity implementation.
- Full signed macOS unit gate: 163 tests in 25 suites passed.
- `make format-check`: 0/719 files require formatting.
- `make localization-check`: 9/9 localized resources have parity.
- `make build-ios`: signed generic iOS build succeeded and built the embedded
  Watch app dependency. `make build-macos`: signed universal macOS build
  succeeded.
- Producer scan confirms `WatchAppStore` no longer contains the shared literal;
  the remaining explicit `watch-ui-audit` values are isolated UI audit fixture
  payloads rather than production producer identity.
- No `TEST-SCAFFOLD` was introduced. Xcode processes exited normally; no
  simulator was created. Real paired-hardware queued-delivery verification is
  a separate release/device gate per `Docs/Testing.md`; it is not required to
  prove this local metadata change and was not run.
