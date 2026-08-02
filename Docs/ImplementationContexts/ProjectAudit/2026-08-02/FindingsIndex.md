# Findings Index

Status: complete

Only the primary agent edits this file. Candidate findings remain in owner files until independently checked. Confirmed findings are deduplicated by root cause and assigned stable IDs (`AUD-001`, `AUD-002`, ...).

| ID | Severity | Category | Root cause | Evidence | Owner review | Primary validation |
| --- | --- | --- | --- | --- | --- | --- |
| AUD-001 | high | latent-bug, hack, security/privacy | Startup suppresses authoritative sync-conflict read failure and performs write-side work while safety state is unknown | `timetracker/Stores/Facade/TimeTrackerStore+Configuration.swift:47` | PRI-001, PSS-001 | resolved and verified 2026-08-02 |
| AUD-002 | medium | latent-bug, durability | Corrupt full-reconciliation attempt is quarantined as absence, permitting incremental continuation from an old cursor | `timetracker/Services/SystemIntegration/PersistentHistoryLaneCursorStore.swift:256`, `:537` | PSS-002 | resolved and verified 2026-08-02 |
| AUD-003 | medium | latent-bug, availability | Corrupt reset-epoch fence fails closed but has no conservative repair path; registration, lanes, and reset all remain disabled | `timetracker/Services/SystemIntegration/PersistentHistoryLaneCursorStore.swift:100`, `:110`, `:431` | PSS-003 | resolved and verified 2026-08-02 |
| AUD-004 | medium | performance, latent-bug, code-smell | Recurrence lifecycle loads all quantity-entry and Pomodoro history despite the active-row bounded contract | `timetracker/Services/Tasks/TaskRecurrencePersistenceState.swift:22` | DCP-003 | resolved and verified 2026-08-02 |
| AUD-005 | medium | performance, code-smell | Checklist reorder validates scoped items, then refetches and materializes the entire checklist table | `timetracker/Services/Checklist/StoreScopedChecklistCommandCoordinator.swift:130`, `timetracker/Commands/ChecklistCommands.swift:89` | PRI-003, DCP-002 | resolved and verified 2026-08-02 |
| AUD-006 | medium | latent-bug, concurrency, code-smell | Two bounded cross-process lock waits calculate elapsed timeout with adjustable wall time | `timetracker/Services/SystemIntegration/PathFileLock.swift:46`, `timetracker/Services/SystemIntegration/SyncConflictService+StateLock.swift:45` | PRI-004, DCP-001 | resolved and verified 2026-08-02 |
| AUD-007 | medium | test latent-bug | Preference failure tests unlink SQLite stores while SwiftData owners can still hold descriptors | `timetrackerTests/Preferences/PreferenceCommandValidationTests.swift:178`, `timetrackerTests/Preferences/SyncedPreferenceMigrationFailureTests.swift:8` | UI-TEST-001 | resolved and verified 2026-08-02 |
| AUD-008 | medium | code-smell, over-engineering | Replaced AI task-plan network/mutation stack remains callable and compiled despite zero production callers | `timetracker/Services/LLM/LLMTaskPlanService.swift:1`, `timetracker/Services/Tasks/StoreScopedAITaskPlanCommandCoordinator.swift:1`, `timetracker/Stores/Facade/TimeTrackerStore+AITaskPlanCommands.swift:73` | PRI-002 | resolved and verified 2026-08-02 |
| AUD-009 | medium | code-smell, test-gap | AI review presentation couples async workflow with destructive/diff policy that cannot be verified independently | `timetracker/Features/Tasks/Generation/AITaskWorkspacePlanGeneratorViews.swift:4` | UI-SMELL-003 | resolved and verified 2026-08-02 |
| AUD-010 | low | latent-bug, protocol drift | Watch command producer uses shared literal `"watch"` rather than stable per-device `watch-UUID` | `timetrackerWatchApp/WatchAppStore.swift:29` | UI-PLATFORM-002 | confirmed; impact currently limited |
