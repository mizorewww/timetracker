# Next Development Plan

Status: current future roadmap only. Completed restructurings and retired `Audit-*.md` snapshots live in git history.

Architecture documents explain where code belongs; this plan explains what to build next and what "done" means.

## Product Direction

Time Tracker should be a reliable local-first time ledger for everyday work and life. Improve trust and daily usefulness rather than adding isolated screens: capture loose items quickly in Inbox; organize work and life into categories and task trees; track real time through `TimeSegment` as the ledger fact; honor an explicit task estimate as the user's plan and otherwise use checklist progress only when there is enough evidence; explain forecasts instead of inventing numbers; keep iCloud, App Intents, Live Activity, Widget, Watch, and future system entry points on the same command layer; prefer native Apple controls over custom UI.

## Open External Verification Gates

Code-side integrations and provisioning are in place; these still need signed runtime/hardware verification outside a source-only review:

- App Group-backed Widget snapshot sharing on a real device (profiles now include `group.me.mezorewww.timetracker`).
- Watch durable command queue, typed terminal result, offline recovery, retry/discard, Always On and power behavior on a paired Watch/iPhone.
- Live Activity permission, Dynamic Island, stale/end, concurrent activities, and low-power behavior.
- CloudKit concurrent edits with an offline old device and mixed app/schema versions.

Keep app and widget entitlements aligned to the same App Group; do not fall back to app-local storage. Automatic signing stays enabled with team `LT98S43NKA`; none of these gates may be bypassed by disabling signing.

## Not In The Next Minor Version

Team collaboration; billing/invoicing; full calendar two-way sync; black-box Core ML forecasting; a web app; drag-and-drop category reassignment unless native behavior is reliable on all target platforms.

## Release Gates

Release criteria are owned by [Testing](Testing.md) and [AGENTS.md](../AGENTS.md). Before shipping a minor version: `make test` green on the frozen tree with xcresult evidence and no owned simulator/process residuals; generic iOS and macOS Release builds pass with automatic signing and expected entitlements; a normal-text-size manual smoke test passes on iPhone, iPad, and macOS (Inbox, Tasks, Today, Pomodoro, Analytics, Settings, sync/recovery, JSON export, countdown); no user-facing string is missing from any of the three locales; every schema change has an old-store compatibility test; performance-sensitive changes carry a seeded Release trace; and production Local/iCloud/fallback stores never physically purge tombstones.
