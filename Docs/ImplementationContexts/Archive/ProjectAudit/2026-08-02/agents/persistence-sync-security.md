# Persistence, Sync, Security, Networking, and Codable Audit

Status: Complete

- Current status: `complete`
- Assigned scope: SwiftData schema and migration; repositories; CloudKit/preferences sync, conflict handling and recovery; durable local files and queues; LLM networking, credentials, Keychain and privacy; Codable and transport validation.
- Explicit exclusions: UI/HIG quality except where it exposes a persistence/security contract; production and test modifications; runtime actions that mutate stores, iCloud, Keychain, network services, simulators, or installed apps; generic test-quality review outside durable/security/compatibility counter-evidence.

## Skills and project documents read

- `AGENTS.md`
- `/Users/aac6fef/.codex/skills/axiom-audit-swiftdata/SKILL.md`
- `/Users/aac6fef/.codex/skills/axiom-audit-database-schema/SKILL.md`
- `/Users/aac6fef/.codex/skills/axiom-audit-storage/SKILL.md`
- `/Users/aac6fef/.codex/skills/axiom-scan-security-privacy/SKILL.md`
- `/Users/aac6fef/.codex/skills/axiom-audit-networking/SKILL.md`
- `/Users/aac6fef/.codex/skills/axiom-audit-codable/SKILL.md`
- `/Users/aac6fef/.codex/skills/axiom-testing/SKILL.md`
- `/Users/aac6fef/.codex/skills/axiom-testing/skills/swift-testing.md`
- `/Users/aac6fef/.codex/skills/axiom-testing/skills/testing-async.md`
- `Docs/ImplementationContexts/Archive/ProjectAudit/2026-08-02/DocumentationStandard.md`
- `Docs/ProjectMap.md`
- `Docs/Architecture.md`, `Docs/CodeGuide.md`, `Docs/Testing.md`, `Docs/PrivacyAndSecurity.md`.
- Relevant accepted decisions read from `Docs/AgentDecisions.md`: AD-001/002/003/005/007/014/015/018/022/023/027/030/033/034/035/036/038/058/060/063/069/073/074/076/078/081/082/084/087/094/098/099/101/104/107/108/109/110/111/115/127/128/129/130/132/133/137.

## Files and directories inspected

- Audit instructions and required skill files listed above.
- Source inventory: 695 Swift/plist/entitlement/privacy-manifest files across app and extension targets.
- Initial focused inspection: schema/model registry/migration files; app and Health container construction sites; storage locations and durable-file owners; LLM transport/credential surface; sync state/snapshot file families; Codable/JSON call sites; Watch/Widget persistence boundaries.

## Searches and commands used

- `wc -l` over required skill and project documents to establish read scope.
- `sed -n` segmented full reads of all six required Axiom skill files.
- `sed -n` reads of `AGENTS.md`, the audit documentation standard, and `Docs/ProjectMap.md`.
- Segmented full reads of `axiom-testing`, `swift-testing.md`, and `testing-async.md`, required before using migration/security tests as counter-evidence.
- `rg --files` source inventory and focused directory listings.
- Every Phase 1 and Phase 2 grep required by the six selected auditors was run separately: SwiftData model/container/migration/sync/storage and ten anti-pattern surfaces; raw SQLite/GRDB framework, DDL, transaction, FK and destructive migration patterns; storage locations/channels/protection/backup/secret patterns; Security/Privacy manifest, entitlements, Required Reason API, Keychain, logger, URL, secret/signature and ATS patterns; networking framework/protocol/lifecycle/deprecated/socket/IP/waiting-state patterns; Codable type/codec/strategy/legacy JSON/manual JSON/`try?`/DateFormatter/enum/catch patterns.
- `sed -n` full-context reads started for `SchemaMigrationPlan.swift`, `SchemaModels.swift`, `SchemaChecklistLegacyModels.swift`, and `TimeTrackerModelRegistry.swift`.
- `ls -la Docs/ImplementationContexts/Archive/ProjectAudit/2026-08-02/agents` to confirm the log directory did not yet exist.

## Working maps

### SwiftData map

- Main current schema is V14 (`1.13.0`) with 18 current user models; the isolated Apple Health replica has 3 models and its own V1 schema.
- Main migration plan registers V1 through V14 with contiguous stages. V4→V5 and V9→V10 are custom; all others are lightweight.
- No `@Model struct`, `@Relationship`, `@Transient`, `@Attribute(.externalStorage)`, or UI `@Environment(\.modelContext)` usage was found. Relationships use UUID references.
- Production main Cloud configuration uses private CloudKit; local/demo/emergency/test and Apple Health configurations explicitly disable CloudKit. Health replica uses a separate store and current factory also has an in-memory fallback.
- Fresh explicit contexts are created by store-scoped mutation transactions, background projection workers, repositories, system actions and fallback recovery; autosave is explicitly disabled at the transaction owner.
- Current/legacy schema models are deliberately separated via frozen Inbox/Checklist snapshots; current registry derives directly from V14.

### Database schema map

- Persistence is SwiftData/Core Data backed; no GRDB, SQLite.swift, sqlite-data, raw SQLite DDL, raw SQL migrations, FK pragmas, `INSERT OR REPLACE`, or ad-hoc destructive schema operations were found.
- Schema ordering is entirely `VersionedSchema` + `SchemaMigrationPlan`, so the raw-SQL anti-pattern family is not applicable.

### Storage map

- Business facts use SwiftData. Durable recovery state and task-draft recovery live under Application Support. Widget/Watch queues use bounded App Group or target-local UserDefaults payloads.
- LLM key uses Keychain. No token/key direct file write was found.
- `DurableLocalFile` applies atomic same-directory publish, iOS first-unlock protection and optional backup exclusion; Health replica separately applies first-unlock protection and backup exclusion.
- No Documents, Caches, iCloud Drive, or persistence-intent `tmp` use was found in production Swift.

### Security and networking map

- Main app, Widget and Watch have privacy manifests; Live Activity does not. Main iOS/macOS and Widget entitlement files exist. No ATT API or arbitrary ATS exception was found.
- Network traffic is confined to the LLM URLSession transport. It uses a dedicated ephemeral session; no Network.framework, legacy reachability/stream/socket/manual DNS/hardcoded-IP surface was found.
- Keychain is the credential boundary; CryptoKit is used for deterministic hashing/identities and snapshot fingerprints. No repository hardcoded secret signature was found.
- Logging surface is small and structured except an explicitly named Cloud sync smoke runner; initial secret-log patterns returned no match.

### Serialization map

- Codable spans local recovery, sync snapshots/manifests, Widget/Watch transports, LLM request/response/tool DTOs, draft recovery and export. Most actor-crossing DTOs are explicitly Sendable.
- Date strategies are explicit for draft recovery (`millisecondsSince1970`), user export/AI workspace (`iso8601`), while local sync/manifests intentionally use matching default Date strategies.
- `JSONSerialization` is limited to arbitrary tool-argument validation, state-format discrimination, preference JSON fragment validation, one UI-audit fixture builder and WatchConnectivity property-list dictionaries.
- `try?` decode/encode sites are retained as review candidates until each failure contract and surrounding validation/fallback is checked.

## PSS-001 — Startup suppresses the authoritative sync-conflict prompt read failure

- Status: confirmed
- Severity: high
- Category: latent-bug | hack | security/privacy
- Confidence: high
- Evidence: `timetracker/Stores/Facade/TimeTrackerStore+Configuration.swift:47-58`, with write-side continuation at `timetracker/Stores/Facade/TimeTrackerStore+Configuration.swift:61-108`.
- Contract: AD-074 makes `SyncConflictService.prompt()` a throwing boundary and explicitly says an unreadable authoritative state must never be reported as “no conflict.” `Docs/Architecture.md:283` likewise requires prompt assembly to throw so corrupt/oversized state enters explicit recovery. Startup recovery must remain read-only until the protected local and Cloud branches are known.
- Execution path: an application-state store starts while its authoritative conflict manifest/slot is corrupt, oversized, inaccessible, or otherwise unreadable. `prompt()` throws; `try?` converts that to `nil`; `pendingSyncConflict` remains nil, so startup skips `configureCloudRecovery` and reaches sensitive-preference migration, legacy migrations, seeding, refresh and reconciliation before the later bootstrap attempt.
- Impact: an unknown conflict state is temporarily treated as safe and startup writes can run before recovery establishes whether the local and Cloud branches diverge. Later bootstrap recovery cannot retroactively make those writes satisfy the read-only barrier.
- Why this is not intentional: every other direct production `prompt()` caller inspected uses a throwing `do`/`try` path. AD-074 was introduced specifically to remove this failure suppression.
- Counter-evidence checked: the complete `configureIfNeeded`, `configureCloudRecovery`, `bootstrapSyncConflictStateIfNeeded`, all direct `prompt()` callers, `SyncConflictPromptRefresh` retry/preserve-last-known logic, and configuration/prompt test searches. Bootstrap retries twice and may recover from the independent protected snapshot, reducing the chance of permanent loss, but it occurs after the write-side operations in this path. No test injects an initial prompt read failure and proves zero startup writes. This independently confirms and deduplicates with primary finding `PRI-001`.
- Recommendation: make the initial prompt read a throwing startup gate. On failure, enter a read-only recovery/diagnostic state or abort write-side configuration before migrations, seeding and other startup effects. Add one lifecycle/command-boundary regression contract with a failing prompt loader and an independent sentinel proving no startup write occurred.

## PSS-002 — A corrupt full-reconciliation attempt is treated as if no attempt existed

- Status: confirmed
- Severity: medium
- Category: latent-bug | durability | test-gap
- Confidence: high
- Evidence: `timetracker/Services/SystemIntegration/PersistentHistoryLaneCursorStore.swift:256-283`, `timetracker/Services/SystemIntegration/PersistentHistoryLaneCursorStore.swift:537-571`, and `timetracker/Services/SystemIntegration/PersistentHistoryProjectionDriver.swift:245-275`.
- Contract: AD-137 and `Docs/Architecture.md:275` make the durable attempt file the crash marker that provides at-least-once recovery after an interrupted full reconciliation. Presence of an unreadable attempt cannot safely mean “no interrupted reconciliation,” because its bytes may have been published before the scan/effect/cursor acknowledgement finished.
- Execution path: a full reconciliation publishes its attempt file, then the process exits or the file is damaged before `establishAfterFullReconciliation` removes it. On the next run, `loadAttemptWithExclusiveAccess` quarantines an oversized or malformed attempt and returns `nil`; `load` then accepts an otherwise valid old cursor as `.ready`; the driver runs incrementally rather than re-running the interrupted full reconciliation.
- Impact: a lane can skip the full current-state publication that the attempt was designed to force. Widget, Watch, Live Activity, or sync-snapshot state can remain stale when the prior full effect did not complete, with convergence deferred until some unrelated future full-reconciliation trigger.
- Why this is not intentional: cursor corruption already maps to `.requiresFullReconciliation`; only attempt corruption collapses to absence. Quarantine is appropriate, but discarding the recovery fact is not.
- Counter-evidence checked: complete attempt begin/load/establish flow, cursor load/advance flow, and driver full/incremental selection. Attempt identity is compared before acknowledgement and successful full reconciliation removes it atomically under the durable-root lock. Those safeguards handle valid attempts, not a quarantined malformed one. Test search found reset cleanup coverage but no malformed/oversized attempt recovery contract.
- Recommendation: return a typed attempt-load result (`missing`, `present`, `corrupt`) and map both `present` and `corrupt` to `.requiresFullReconciliation(.interruptedFullReconciliation)` after quarantine. Retain a behavior test whose oracle is that the next invocation is `.fullReconciliation`, not merely that a quarantine file exists.

## PSS-003 — Corruption of the retained reset-epoch sidecar permanently disables projections and recovery reset

- Status: confirmed
- Severity: medium
- Category: latent-bug | availability | durability | test-gap
- Confidence: high
- Evidence: `timetracker/Services/SystemIntegration/PersistentHistoryLaneCursorStore.swift:100-159`, `timetracker/Services/SystemIntegration/PersistentHistoryLaneCursorStore.swift:226-241`, and `timetracker/Services/SystemIntegration/PersistentHistoryLaneCursorStore.swift:431-437`.
- Contract: AD-137 and `Docs/Architecture.md:275` require a retained reset epoch to prevent work from a replaced physical store acknowledging a new frontier. The same architecture promises later startup/foreground/commit triggers can recover failed lanes; metadata damage should fail closed without creating a permanent unrecoverable projection outage.
- Execution path: the at-most-4-KiB reset-epoch JSON becomes malformed, unsupported, oversized, or unreadable. `currentEpochWithExclusiveAccess` directly throws and has no quarantine/repair state. New cursor-store registration fails; all existing cursor operations also fail epoch matching; `advanceForStoreReset` first calls the same decoder and therefore cannot advance/repair the fence during Cloud recovery.
- Impact: all four persistent-history lanes stop converging, and the normal physical-store reset path cannot heal the sidecar. The user may retain correct SwiftData facts while sync protection snapshots and system surfaces remain indefinitely stale until manual file intervention/reinstall.
- Why this is not intentional: throwing rather than assuming epoch zero is the correct safety posture, because accepting zero could acknowledge stale work. The bug is the absence of any locked, conservative recovery transition after failing closed, not the refusal to decode corrupt bytes.
- Counter-evidence checked: the full reset-fence type, every cursor epoch check, Cloud-recovery cleanup test coverage, and architecture/AD reset rules. Atomic `DurableLocalFile` publication makes spontaneous corruption unlikely and the hard safety guarantee is preserved. Existing tests verify that reset advances and preserves a valid fence, but not corrupt/oversized fence recovery.
- Recommendation: define an explicit corrupt-fence recovery under the store mutation lock and durable-root lock: quarantine the sidecar, invalidate/remove every lane cursor and attempt, publish a new nonzero epoch, then force all lanes through full reconciliation. Do not silently substitute epoch zero. Add a durable integration contract covering malformed and oversized sidecars plus stale-coordinator non-acknowledgement.

## Rejected candidates and counter-evidence

### PSS-R01 — SwiftData schema registration or migration gap

- Status: rejected
- Severity: high
- Category: latent-bug
- Confidence: high
- Evidence: `timetracker/Models/SchemaMigrationPlan.swift:5-67`, `timetracker/Models/TimeTrackerModelRegistry.swift:3-14`.
- Contract: every historical schema must remain registered and every adjacent version needs a migration stage; the current registry must match V14.
- Execution path: reviewed V1 through V14 registration/stages, both custom migrations, frozen legacy checklist/inbox shapes, current container factories and the isolated Health V1 store.
- Impact: no gap found. Raw SQL/GRDB destructive-migration patterns are not applicable because the project uses versioned SwiftData schemas.
- Why this is not intentional: not applicable after rejection.
- Counter-evidence checked: all schema model lists, current registry and container configuration sites; no missing adjacent stage or Cloud-enabled Health store was found.
- Recommendation: retain existing old-store compatibility gates; no production change from this audit.

### PSS-R02 — Task draft and sidecar writes lack protection, atomicity, or backup policy

- Status: rejected
- Severity: high
- Category: security/privacy | durability
- Confidence: high
- Evidence: `timetracker/Services/Tasks/TaskDraftRecoveryStore.swift:75-86`, `timetracker/Services/SystemIntegration/DurableLocalFile+Writing.swift:17-54`.
- Contract: recovery data under Application Support must be bounded, atomically published, protected after first unlock and excluded from backup.
- Execution path: inspected the draft codec/store and the complete durable read/write/lock/quarantine implementation.
- Impact: no bypass found. Draft payloads are bounded; corrupt files are removed/quarantined as specified; writes use same-directory temporary files, restrictive permissions, protection, backup exclusion, synchronization and atomic rename.
- Why this is not intentional: not applicable after rejection.
- Counter-evidence checked: Application Support locations, symlink/path containment, directory/file fsync, quarantine limits and other durable owners.
- Recommendation: no change.

### PSS-R03 — LLM credential or HTTP transport exposes secrets or permits unbounded/default-session traffic

- Status: rejected
- Severity: high
- Category: security/privacy | networking
- Confidence: high
- Evidence: `timetracker/Services/SystemIntegration/LLMCredentialStore.swift:27-27`, `timetracker/Services/SystemIntegration/LLMCredentialStore.swift:77-101`, `timetracker/Services/LLM/LLMSecureHTTPTransport.swift:4-23`.
- Contract: API keys remain device-local in Keychain; transport uses the validated HTTPS boundary with bounded responses and no persistent URL cache/cookies.
- Execution path: inspected Keychain add/update/read/delete queries, redirect/endpoint validation, buffered and streaming response paths, cancellation and status handling.
- Impact: no secret file/logging, synchronizable credential, ATS exception, hardcoded key, or unbounded response path was found.
- Why this is not intentional: `AfterFirstUnlockThisDeviceOnly` is intentionally weaker than when-unlocked access so background Shortcuts/Cloud operations can read the key, while remaining device-only and non-synchronizable.
- Counter-evidence checked: all URLSession construction and credential call sites; networking is confined to the LLM transport and uses an ephemeral session with a 2-MiB cap.
- Recommendation: no change.

### PSS-R04 — `PreferenceJSON.encode` can persist its `"null"` compatibility fallback

- Status: rejected
- Severity: medium
- Category: latent-bug | serialization
- Confidence: high
- Evidence: `timetracker/Models/PreferenceJSON.swift:20-43`, `timetracker/Models/PreferenceJSON.swift:64-119`, `timetracker/Commands/PreferenceCommands.swift:18`.
- Contract: a failed encoding cannot become a durable preference value.
- Execution path: searched every helper caller and followed values through the preference command boundary.
- Impact: no durable fail-open path found. The compatibility helper can return `"null"`, but persistence canonicalizes against the declared key type with throwing checked decode/encode before mutation; invalid null is rejected for current preference types.
- Why this is not intentional: the source comment explicitly limits the helper to compatibility/non-persistence use, and the command enforces that boundary.
- Counter-evidence checked: preference commands, sync snapshot preflight and facade setters.
- Recommendation: no behavior change; future callers should continue using `encodeChecked` at durable boundaries.

## Open questions and runtime-only verification needs

- No additional runtime-only finding is required to substantiate PSS-001 through PSS-003; each follows directly from reachable error branches and explicit durable contracts.
- The V4→V5 process-global migration staging buffer could theoretically interleave if two legacy containers migrate concurrently in one process, but current production container construction is singleton/sequential and static review did not establish a reachable concurrent migration. It remains unreported rather than overstating a hypothetical.

## Completion checklist

- Assigned scope, exclusions, skills, documents, source maps and searches are recorded.
- Three confirmed findings use the binding finding template; the high finding is cross-validated and deduplicated with `PRI-001`.
- Four major false-positive families and their safeguards are retained.
- No production or test source was modified; only this audit context file was edited.
- No runtime stores, Keychain items, iCloud state, network services, simulators or installed apps were mutated.
