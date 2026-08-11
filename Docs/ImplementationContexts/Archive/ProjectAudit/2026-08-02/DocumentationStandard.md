# Audit Documentation Standard

Status: binding for this audit

## Persistence Rule

Every auditor must write its evidence to its assigned file under `agents/` before reporting completion. Update the file during the review, not only at the end, so context survives model compaction or agent interruption. Chat-only findings are discarded.

Each file starts with:

- assigned scope and explicit exclusions;
- skills and project documents actually read;
- files/directories inspected;
- searches or commands used;
- current status: `not-started`, `in-progress`, `complete`, or `blocked`.

## Finding Template

Use one section per candidate:

```markdown
## CANDIDATE-ID — Short title

- Status: candidate | confirmed | rejected | needs-runtime-verification
- Severity: critical | high | medium | low
- Category: bug | latent-bug | hack | code-smell | over-engineering | test-gap | security/privacy | performance
- Confidence: high | medium | low
- Evidence: `relative/path.swift:line`
- Contract: architecture, accepted AD, user-visible behavior, platform API, or independently derived invariant
- Execution path: concrete inputs/events needed to reach the behavior
- Impact: user/data/security/maintenance consequence
- Why this is not intentional: relevant safeguard or decision checked
- Counter-evidence checked: callers, tests, fallback, actor/lock/transaction boundary, platform guards
- Recommendation: smallest safe correction or verification step
```

No candidate becomes confirmed without precise source evidence and a stated contract. Line numbers must be refreshed immediately before handoff.

## Severity

- `critical`: credible data loss, secret disclosure, destructive corruption, or broadly reachable crash with no practical recovery.
- `high`: reachable incorrect durable behavior, race, deadlock, migration/sync failure, or common-path crash.
- `medium`: bounded latent bug, meaningful performance failure, fragile ownership, or duplication likely to cause divergence.
- `low`: localized maintainability smell or narrow edge case with limited impact.

Severity measures impact and reachability, not code ugliness.

## Hack And Smell Standard

Report a hack only when code deliberately bypasses a declared boundary, relies on undocumented temporal/order behavior, hides a failure, or uses a brittle special case instead of the canonical abstraction. Words such as `TODO`, `FIXME`, `workaround`, `legacy`, and `temporary` are leads, not findings.

Report a code smell only with at least one concrete cost: duplicated invariant, mixed ownership, unbounded state, broad invalidation, hidden coupling, unsafe type erasure, excessive branching, or inability to verify behavior independently.

## Over-Engineering Standard

Before reporting over-engineering, identify:

1. The active behavior/risk the mechanism protects.
2. The accepted AD or security/sync/migration contract that may justify it.
3. The simpler design and which guarantees it retains or drops.
4. Evidence that the mechanism has no second caller, no measured risk, or disproportionate maintenance burden.

Do not use file count, type count, protocol count, or line count alone as evidence. In this project, explicit locks, bounded queues, snapshot validation, migration layers, and system-surface projections may be necessary safeguards.

## Cross-Validation

For every high/critical candidate and every over-engineering claim:

- read the complete containing function/type;
- inspect all direct callers and relevant tests;
- check `Docs/Architecture.md`, `Docs/CodeGuide.md`, and matching accepted AD decisions;
- search for an existing issue explanation, fallback, or invariant;
- record counter-evidence even when the finding remains valid.

The primary agent deduplicates by root cause, not merely `file:line`. Multiple symptoms caused by one invariant failure become one finding with multiple evidence locations.

## Test Review Rules

Tests are reviewed under `axiom-testing` and `axiom-audit-testing`. Do not recommend source-string scan tests, arbitrary sleeps, duplicate layer-by-layer contracts, or tests whose oracle mirrors production. Missing coverage is a finding only for a durable/user/security/compatibility contract with a realistic regression path.

## Completion Checklist

- Assigned scope and exclusions are explicit.
- All inspected files/searches are recorded.
- Every candidate follows the template.
- False positives and rejected candidates are retained with the rejection reason.
- High/critical and over-engineering candidates include counter-evidence.
- No production or test source was modified.
- Open questions and runtime-only verification needs are listed.
