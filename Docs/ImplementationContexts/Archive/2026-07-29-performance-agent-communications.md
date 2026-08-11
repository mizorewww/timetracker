# Performance Hardening — Agent Communications

Status: complete

Related memory: [performance hardening](2026-07-29-performance-hardening.md)

This log records delegated scope, ownership boundaries, findings, and handoffs. Agents
must not launch builds, tests, simulators, virtual machines, Instruments, or other shared
runtime resources unless the primary agent explicitly assigns a batch.

## Coordination log

### 2026-07-29 — Primary agent

- Created branch `codex/performance-hardening-2026-07-29`.
- Reserved all build, test, simulator, macOS virtual-machine, and Instruments ownership
  for the primary agent until explicit delegation.
- Assigned independent read-only audits for:
  - memory ownership and lifecycle risks;
  - energy/background/timer/network/disk-I/O risks;
  - Swift/collection/actor-isolation performance risks.
- Requested evidence with exact file/line references, impact reasoning, and proposed
  regression coverage. No source edits are authorized during the first audit pass.

## Handoffs

### Swift/collection audit

- Completed read-only; no source edit or runtime resource.
- Reported two critical paths: recurrence startup/foreground state materializes all
  ledger history, and AI workspace tool execution repeatedly rebuilds/canonicalizes
  the full workspace on MainActor.
- Reported high-value bounded-query candidates in timer admission, quantity entry, and
  Pomodoro short-cancel, plus checklist reorder and sibling queries.
- Confirmed analytics overlap/timeline/rollup core paths already have meaningful
  indexing, detached projection, and large-data budgets.

### Energy audit

- Read-only; no runtime resource.
- Found that `cloudExportFinished` is coalesced into an unconditional
  `.remoteImportCompleted` refresh/projection path, duplicating expensive work after
  local writes.
- Found HealthKit `.immediate` background delivery remains registered after the user
  hides the Health timeline.
- Found two to three independent 1 Hz timer presentations on Today, periodic idle
  metrics/timeline work, full sync-snapshot encoding/fsync amplification, system
  projection payload/history duplication, and foreground account-check duplication.
- Confirmed there are no repeating Foundation timers, location/audio/background URL
  sessions, runaway animations, or provider polling. LLM requests are user-initiated
  and cancellation-aware.
- Handoff priority was pure export catch-up, Health observer leases, shared Today
  clock, then durable snapshot/projection deduplication. The primary agent implemented
  and behavior-tested the first item; the UI/Health/durability changes remain separate
  projects because they require wider contracts and device/simulator evidence.

### Memory/lifecycle audit

- Completed read-only across 687 non-test Swift files; no runtime resource.
- Reported zero Critical, four High, and two Medium findings.
- High findings: missing `MacBlossomColorPresenter.deinit` fallback for its process
  event monitor/window observers; sync-conflict refresh task retaining the scene store
  across a cancellation-unaware loader; checklist visual failure metadata growing by
  deleted item UUID; and system-projection drain tasks lacking shutdown/timeout.
- Medium findings: unbounded scene feedback FIFO and startup Cloud import reason
  buffer. Confirmed most other observer/task/cache owners have paired cancellation or
  explicit caps and found no repeating Timer or Combine sink family.
- The primary agent implemented the checklist metadata pruning with a 10,000-ID
  regression. The other findings need injectable shutdown/monitor contracts rather
  than an untested lifecycle-only patch.

### Primary-agent integration decisions

- All runtime ownership remained with the primary agent as assigned.
- Accepted and verified four bounded changes: recent-ledger index removal, active-only
  recurrence segment lookup, session-scoped Pomodoro cancellation, and pure-export
  sync catch-up suppression.
- Accepted and verified one memory-bound change: checklist failure/retry metadata
  pruning and global release.
- Deferred Today shared-clock, HealthKit lease/background-delivery, snapshot fsync
  reuse, projection batch scans, and async-owner shutdown work to focused follow-ups;
  each crosses UI, physical-device, durability, or cancellation contracts that cannot
  be honestly closed by this static audit alone.

### 2026-07-29 — Primary-agent closeout

- Integrated the accepted findings in commit `e9bf30d3`.
- Ran the final signed macOS unit gate (1,579 tests), generic iOS build, formatting,
  localization, and hook checks successfully.
- Performed no macOS UI automation; no macOS virtual machine was needed.
- Audited all assigned runtime ownership empty and closed every delegated read-only
  audit with no unmerged edits or retained resources.
