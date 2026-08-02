# Testing

Status: current verification policy

Reviewed: 2026-08-02

## Purpose

The test suite is a small set of independent product and data-safety contracts. It is not a second implementation, a source-layout specification, or a catalogue of every state permutation.

The 2026-08-02 audit reduced the suite from 1,738 static declarations to 151 declarations. The pre-audit default run executed 1,584 Swift Testing cases plus five skipped XCTest live cases; the retained default unit run executes 147 cases. The repository ceiling is 158 declarations. Adding a test therefore requires removing or consolidating an equal number of lower-value tests.

Count declarations with:

```sh
rg -n '^\s*@Test' timetrackerTests timetrackerUITests | wc -l
rg -n '^\s*(override )?func test' timetrackerTests timetrackerUITests | wc -l
```

Parameterized data must stay small and meaningful. Do not use a large argument table to bypass the declaration budget.

## Default Gates

Run signed macOS unit tests through the Makefile:

```sh
make test
```

Focused diagnosis may use the same entry point:

```sh
make TEST_ONLY=timetrackerTests/CoreLLMResponseTransportTests test
```

The final unit result for a shipping change must use `make test` without `TEST_ONLY`.

Other repository gates remain separate:

```sh
make localization-check
make format-check
make build-ios
make build-macos
make test-versioning
```

Keep `CODE_SIGN_STYLE=Automatic` and team `LT98S43NKA`. Never disable signing to make a gate pass.

Unit tests construct the facade with `makeTestStore(...)`. The test host, defaults, sync state and widget snapshot storage must remain isolated from the installed app. `TestHostIsolationTests` is the safety gate for that boundary.

## What Deserves An Automated Test

Add or retain a test only when all of these are true:

1. It protects a user-visible outcome, durable-data invariant, security boundary, compatibility boundary, or high-risk cross-model transaction.
2. Its expected result comes from the product contract, a frozen external fixture, or a simple independently calculated oracle—not another production implementation of the same algorithm.
3. A realistic regression can make the test fail without editing the test at the same time.
4. It is the closest useful boundary to the risk. The same rule is not repeated at policy, repository, store, facade and UI layers.
5. The test is deterministic, isolated and materially cheaper than the failure it prevents.

Prefer one end-to-end command-boundary test over several implementation-unit tests when a durable write spans multiple models. Prefer one migration fixture that reopens a real disk store over many constructor/default assertions.

For a reported bug, first write the smallest test that fails for the user-visible or durable-data consequence. Do not infer the expected value from current production output; that merely freezes the bug.

## Retained Contract Areas

The compact suite intentionally concentrates on:

- SwiftData schema migration and disk-store reopen compatibility;
- snapshot preflight rejection, deterministic LWW merge and tombstone dominance;
- Cloud recovery read-only/failure behavior and protection of committed local data;
- preference batch validation, secret migration rollback and test-host isolation;
- timer, checklist, manual ledger and Pomodoro store-scoped atomic mutations;
- recurrence timezone/day identity and direct-work eligibility;
- future-dated Cloud winners that must not revive edited or deleted ledger facts;
- bounded LLM response parsing, cancellation, status precedence and response-size limits;
- signed entitlement and Privacy Manifest declarations;
- the width-driven adaptive shell and one explicitly audited Live Activity system-surface path.

Authentication and in-app purchases are not present in this product. If either is added, its trust boundary must replace lower-value coverage rather than silently expanding the suite.

## Tests We Do Not Add

Do not add tests that:

- read Swift source or project files and assert strings, symbols, call order, file names or line counts;
- mirror private state machines, cache registries, fault-point sequences or internal helper calls;
- pin prompt prose, localized copy, exact view hierarchy, column order or layout point constants;
- compare one production implementation with another implementation of the same rule;
- assert only that the current output has not changed without establishing why that output is correct;
- use arbitrary sleeps to prove asynchronous behavior or non-occurrence;
- call a live model/server from the default suite or pass by skipping when credentials are missing;
- enumerate every invalid value when one representative boundary plus a property-level invariant is enough;
- repeat a command invariant at policy, repository, facade and UI layers.

Property-list/resource validation is allowed when it parses the shipped artifact itself, such as entitlements or Privacy Manifests. That is different from scanning implementation source.

## Async And External Systems

Async tests wait on an observable condition, confirmation, expectation or injected clock. A short poll is acceptable only when the condition is the assertion boundary and the poll has a strict timeout; a fixed delay followed by an assertion is not.

Network tests use injected transports and byte/status/error fixtures. Live LLM verification is a manual smoke check and must never be reported as deterministic regression evidence.

CloudKit, HealthKit, Widget, Watch and Live Activity simulator results are diagnostic. Real-device entitlement, container, background-delivery and system-presentation checks remain separate release evidence.

## UI Verification

UI automation is reserved for a few high-value platform integration paths. The retained UI target is nonparallelizable because it launches one stateful app and may capture ordered system surfaces.

Run a retained case through the Makefile:

```sh
make UI_TEST_ONLY=timetrackerUITests/AdaptiveShellUITests/testNowSectionRendersInWhicheverShellIsChosen test-ui-ios
make UI_TEST_ONLY=timetrackerUITests/AdaptiveShellUITests/testNarrowMacKeepsNativeSettingsCapability test-ui-macos
```

UI-only changes start with an acceptance checklist. Verify ordinary interaction, native roles, stable accessibility identifiers, normal text size, relevant compact/regular widths and a screenshot when visual judgment matters. Exact pixel geometry, full copy and private SwiftUI hierarchy do not become regression contracts.

Maximum Dynamic Type, VoiceOver traversal, appearance matrices and additional devices are risk-triggered checks, not a permanent cartesian product. Use them when the changed code affects those behaviors or a regression is reported.

## Migration Fixtures

Current compatibility tests generate old stores from frozen legacy schema declarations in the current source tree. They catch migration wiring failures but do not prove compatibility with an actually shipped binary.

The higher-confidence replacement is a small set of synthetic SQLite bundles generated by released tags with their contemporaneous toolchains. Each fixture must include fixed identities, schema/app/build metadata and SHA-256 hashes, then be copied to a unique temporary directory before migration. Add those fixtures by replacing current generated-schema cases, not by increasing the suite budget.

## Performance Verification

Wall-clock microbenchmarks in the app-hosted unit suite were removed because host load and implementation-specific thresholds produced noisy, easily gamed gates. Performance-sensitive changes use:

1. a correctness test proving bounded query shape or incremental result equivalence when that can be observed without source scanning;
2. a seeded Release build;
3. Instruments or signpost evidence before and after the change.

Use Time Profiler for CPU work and Animation Hitches/Core Animation for rendering. Record the exact build, data scale, device and trace in the shipping commit or PR. A one-time trace is evidence for that change, not a permanent test declaration.

## Resource Ownership And Cleanup

Every simulator, UI runner, screenshot or profiling batch has one owner. Record the destination UDID, app/runner identifiers and artifact paths.

After the batch:

1. stop only owned test/profile processes;
2. terminate the tested app and runner on the exact destination;
3. shut down owned simulators and delete simulators created for the batch;
4. close Simulator, DeviceHub or Problem Reporter only if the batch opened them;
5. verify no owned `xcodebuild`, `xctest`, runner, trace process or Booted device remains.

Do not use broad `killall` commands and do not clean another agent's resources.

## Final Evidence

Only the last run against the frozen source state is final evidence. Report the command, pass/fail/skip counts, signing result, relevant UI/device evidence and cleanup. Earlier targeted runs are diagnostics and are never added together to impersonate one complete pass.
