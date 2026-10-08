# Apple Health / HealthKit removal — 2026-10-08

Branch: `feat/remove-apple-health`. Complete removal of the Apple Health
integration (feature moves to a standalone export app).

## Owner decisions

- **D1 — Catalog rows.** The deterministic `A1*` Task/Category/Assignment rows
  stay in the main store as ordinary user tasks/categories. No tombstone, no
  migration, no special startup logic. They become user-visible/syncable like
  any other task; ~13 previously sync-only root tasks/categories remain.
- **D2 — JSON export.** `UserDataExport.swift` and
  `SyncConflictService.exportUserData` are deleted. `jsonExport` reverts to the
  business-only `SyncConflictService.exportCloudSyncedData`
  (`timetracker.cloudSyncedData` envelope).
- **D3 — Orphan cleanup.** `AppleHealthLegacyCleanup.runIfNeeded()` runs on the
  real-app container startup path and tolerate-absent deletes
  `AppleHealthReplica.store{,-shm,-wal}` next to the main store plus the two
  device-local `UserDefaults` keys. No schema/migration involvement.
- **D4 — Signing.** HealthKit `PROVISIONING_PROFILE_SPECIFIER` removed. The
  health-introduced `CODE_SIGN_STYLE[sdk=iphoneos*] = Manual` override was also
  removed (supervisor-approved) so iphoneos uses automatic signing with team
  `LT98S43NKA`; nothing is disabled.

## Removed test coverage

- `timetrackerTests/Core/AppleHealthTaskCatalogTests.swift` — deterministic
  catalog UUID contract (contract removed with the catalog).
- `timetrackerTests/Lifecycle/AppleHealthReplicaSchemaCompatibilityTests.swift`
  — replica V1 disk-store reopen (store no longer exists).
- `timetrackerTests/Support/AppleHealthReplicaTestSupport.swift` — replica
  fixtures.
- `DataModelContractTests`: `jsonExportIncludesBusinessDataAndAppleHealthReplica`
  and `jsonExportEncodesAnExplicitEmptyHealthReplica` and
  `jsonExportFailsClosedWhenTheHealthReplicaCannotBeRead` plus
  `JSONExportProbeError`. `jsonExportFailureThrowsWithoutMutatingGlobalFeedback`
  retained (business-only envelope).
- `TestSupport` Health store factories, `CoreCloudRecoveryGateTests` ctor args,
  and the staged Health descendant in
  `TaskRecurrenceWorkEligibilityTests.scopedAdmissionPreserves…` (renamed).

## Residual risks

- D1 leaves ~13 synced "ghost" catalog tasks/categories visible on every
  device; retiring them later needs an explicit product decision.
- A still-running older health-capable build could recreate catalog rows against
  the new build; D1 intentionally does not fight this.
- Orphan cleanup deletes `AppleHealthReplica.store*` at first launch of the new
  build only; if a launch never happens the file stays orphaned (harmless,
  backup-excluded). No health JSON payload can be exported any more.
- Signing: the App ID portal capability for HealthKit (if still present) is
  harmless but should be dropped before archive; not editable from the CLI.
