# Testing

Status: current verification policy

## Purpose

The test suite is a small set of independent product and data-safety contracts. It is not a second implementation, a source-layout specification, or a catalogue of every state permutation. Add a test when it protects a documented durable contract; remove it when it is redundant or was explicitly created as temporary scaffolding. The `axiom-testing` skill covers test design in depth.

Count declarations with `grep -rn '^\s*@Test' timetrackerTests | wc -l`. Parameterized data stays small and meaningful — distinct contract boundaries, not an exhaustive mirror of the implementation.

## Default Gates

Run signed macOS unit tests through the Makefile:

```sh
make test
make TEST_ONLY=timetrackerTests/CoreLLMResponseTransportTests test   # focused diagnosis
```

The final unit result for a shipping change must use `make test` without `TEST_ONLY`. Other gates are separate:

```sh
make localization-check
make format-check
make build-ios
make build-macos
```

## Signing And System Capability

Keep `CODE_SIGN_STYLE=Automatic` and team `LT98S43NKA`. Never disable signing to make a gate pass:

- Do not hide signing errors behind `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, or an empty `DEVELOPMENT_TEAM`. Simulator logs showing `Sign to Run Locally` are the normal local-simulator step; generic/device/Release builds must still verify the Apple Development identity, team, profile, and entitlements.
- The canonical APS key is `aps-environment`, not `com.apple.developer.aps-environment`: Automatic Signing can build while silently stripping the unknown key from the generated `.xcent` and the final signature. Capability acceptance compares the source entitlement, embedded profile, `.xcent`, and `codesign -d --entitlements` output.
- Prefer the CLI with the repository scheme and automatic signing; use Xcode UI only for account/profile operations the CLI cannot express.
- Simulators verify layout, navigation, and most domain interaction; they cannot prove App Group, CloudKit account, Watch round-trip, Live Activity system limits, or release profiles on real hardware.

Unit tests construct the facade with `makeTestStore(...)`. The test host, defaults, sync state, and widget snapshot storage must stay isolated from the installed app; `TestHostIsolationTests` gates that boundary.

## What Deserves An Automated Test

Add or retain a test only when all of these are true:

1. It protects a user-visible outcome, durable-data invariant, security boundary, compatibility boundary, or high-risk cross-model transaction.
2. Its expected result comes from the product contract, a frozen external fixture, or a simple independently calculated oracle — not another production implementation of the same algorithm.
3. A realistic regression can make the test fail without editing the test at the same time.
4. It is the closest useful boundary to the risk; the same rule is not repeated at policy, repository, store, facade, and UI layers.
5. It is deterministic, isolated, and materially cheaper than the failure it prevents.

Prefer one end-to-end command-boundary test over several implementation-unit tests when a durable write spans multiple models. Prefer one migration fixture that reopens a real disk store over many constructor/default assertions. For a reported bug, first write the smallest test that fails for the user-visible or durable-data consequence; do not freeze the bug by inferring the expected value from current output.

Retained contract areas: schema migration and disk-store reopen; LWW/tombstone deduplication; ledger math (gross/wall/overlap, day and DST splits, rapid restart); JSON export filtering; preference batch validation, secret migration rollback, test-host isolation; store-scoped timer/checklist/ledger/Pomodoro atomic mutations; AI workspace persistence actor isolation and stale-baseline rejection; recurrence identity and direct-work eligibility; future-dated Cloud winners; LLM response parsing/cancellation/size limits; width-driven adaptive shell and one audited Live Activity surface path.

Do not add tests that read Swift/project source and assert strings, symbols, call order, file names, or line counts; mirror private state machines; pin prompt prose, localized copy, layout constants, or exact view hierarchy; compare two implementations of the same rule; assert only that output has not changed; use arbitrary sleeps; call a live model/server from the default suite; or enumerate every invalid value when one boundary plus an invariant suffices. Property-list/resource validation that parses the shipped artifact (entitlements, Privacy Manifests, migration fixtures) is allowed.

## Async, UI, And Performance

- Async tests wait on an observable condition, confirmation, expectation, or injected clock — never a fixed delay. Network tests use injected transports and byte/status/error fixtures; live LLM verification is a manual smoke check, never deterministic regression evidence.
- UI automation is reserved for a few high-value platform integration paths. The UI target is nonparallelizable because it launches one stateful app. Run retained cases through `make UI_TEST_ONLY=... test-ui-ios` / `test-ui-macos`. Verify ordinary interaction, native roles, stable accessibility identifiers, normal text size, relevant compact/regular widths, and a screenshot when visual judgment matters. Maximum Dynamic Type, VoiceOver traversal, and extra devices are risk-triggered checks, not a permanent cartesian product.
- Performance-sensitive changes keep a correctness test where the result is observable; profile with a seeded Release build when a change is meant to fix a measured slowdown.

## Migration Fixtures

Compatibility tests generate old stores from frozen legacy schema declarations in the current tree; they catch migration wiring failures but do not prove compatibility with a shipped binary. The higher-confidence replacement is a small set of synthetic SQLite bundles generated by released tags with fixed identities, schema/app/build metadata, and SHA-256 hashes, copied to a unique temporary directory before migration. Consolidate weaker generated-schema cases once released fixtures provide stronger coverage.

## Resource Cleanup

After a UI or profiling batch, terminate the tested app and runner, shut down and delete simulators you created (`make test-ui-ios` does this itself), and remove temporary result bundles. Never stop a simulator or process another agent owns. Disk-backed SwiftData failure tests must not unlink a store directory while a live `ModelContainer`/`ModelContext` may still own SQLite sidecar descriptors; use a unique temporary path.

## Final Evidence

Only the last full `make test` on the final source is evidence; report its pass/fail counts. Earlier targeted runs are diagnostics.
