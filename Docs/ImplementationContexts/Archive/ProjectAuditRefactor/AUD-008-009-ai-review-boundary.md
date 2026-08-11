# AUD-008/009 AI Review Boundary

Status: complete

## Scope

- Remove the replaced `LLMTaskPlanService`, its draft/payload model, obsolete
  store-scoped mutation coordinator, mutation result model, and the unused
  `TimeTrackerStore.saveAITaskPlan` entry point.
- Extract the error and depth contracts still used by
  `LLMTaskWorkspacePlanningService` into a service-neutral planning contract.
- Move workspace review counts, destructive classification, stable operation
  identity, title/context, and before/after field mapping out of the 1,402-line
  SwiftUI file into a Foundation-only presentation policy.
- Keep the existing request, cancellation, review, confirmation, stale-preview,
  and Apply behavior unchanged. No new architecture framework or view model is
  introduced.

This follows the AI/HIG control contract: generated changes remain explicitly
reviewable, quantity-goal removal/archive/delete remain confirmation-gated, and
the person retains Cancel, change-request, and retry paths.

## Test record

| Contract | Risk protected | Independent oracle | Boundary | Lifetime |
| --- | --- | --- | --- | --- |
| Every operation kind contributes to the correct create/update/archive/delete/reuse count; reuse is not a mutation | Review summary or Apply count can misdescribe the actual operation list | A manually constructed operation table with one representative of each count bucket | Foundation-only `AITaskWorkspaceReviewPresentation` | Permanent AI safety/presentation contract |
| Archive/delete and quantity-goal removal are destructive; ordinary create/update/reuse and retained goals are not | A destructive generated change could bypass explicit confirmation | Direct before/after task fixtures plus all destructive operation cases | Review policy classification | Permanent AI safety contract |
| Category, task, and checklist updates disclose every changed user-facing field and omit unchanged fields | Review can hide a generated mutation or display a false diff | Direct model pairs with independently enumerated expected field/value changes | Review presentation policy | Permanent AI review contract |
| Duplicate same-kind/entity operations receive stable distinct IDs and ordered accessibility indexes | SwiftUI rows can alias or expose unstable review order | Two identical operation values with expected occurrence indexes 0 and 1 | Review presentation identity | Permanent UI/data contract |

Tests use direct operation/model fixtures rather than the overlay that produces
operations, preserving an independent oracle. No test scaffolding is planned.

## Implementation outcome

- Deleted the replaced 784-line `LLMTaskPlanService`, 338-line
  `StoreScopedAITaskPlanCommandCoordinator`, obsolete mutation result models,
  and the unused `TimeTrackerStore.saveAITaskPlan` facade entry point. The six
  validation failures still used by workspace planning now live in the narrow
  `LLMTaskPlanningError`; legacy-only error cases and the unused depth constant
  were not retained.
- Reduced `AITaskWorkspacePlanGeneratorViews.swift` from 1,402 to 489 lines.
  Request/generation/cancellation/Apply orchestration remains there; review row
  values, safety policy, and rendering now live in separate 190-, 434-, and
  301-line files respectively.
- The presentation and policy files import Foundation only. They own operation
  counts, mutation count, destructive classification (including quantity-goal
  removal), stable duplicate identity, localized context, and complete
  Category/Task/Checklist before→after field mapping. SwiftUI-only symbol and
  tint choices remain in the review view file.
- The Axiom AI and repository HIG/SwiftUI guidance kept generated mutations
  read-only until explicit Apply, retained Cancel/change-request/retry paths,
  and preserved native destructive confirmation. No new architecture framework
  or hidden fallback was introduced.

## Verification and closeout

- Red seam: the new review tests initially failed to compile because counts,
  mutation totals, and destructive presentation properties did not exist. A
  later compile failure caught `localizedKind` still being file-private in the
  old SwiftUI file; moving that semantic label into the pure policy removed the
  final file-level coupling.
- Retained six permanent tests in
  `timetrackerTests/LLM/AITaskWorkspaceReviewPresentationTests.swift` covering
  all planned contracts. Focused gate: 6 tests passed.
- Full signed macOS unit gate: 160 tests in 24 suites passed.
- `make format-check`: 0/718 files require formatting.
- `make localization-check`: 9/9 localized resources have parity.
- `make build-ios` and `make build-macos`: both signed generic Debug builds
  succeeded. This was a structural UI split with no visual or interaction
  change, so no screenshot baseline was altered.
- Swift caller scan found no remaining `LLMTaskPlanService`, `AITaskPlanDraft`,
  old coordinator/mutation-result, `saveAITaskPlan`, or legacy planning-policy
  symbol. No `TEST-SCAFFOLD` was introduced.
- Xcode test/build processes exited normally; no simulator was created or
  owned by this checkpoint.
