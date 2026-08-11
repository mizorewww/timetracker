# AI Workspace Persistence Executor Design

Status: design complete; no production or test change made by this agent

## Question and invariant boundary

This note answers one bounded question: how to move the complete SwiftData
capture and Apply path owned by `StoreScopedAITaskAtomicMutationCoordinator`
off `MainActor` without weakening any accepted data-safety contract.

The following invariants are non-negotiable:

- one `TimerStoreScope` continues to select the existing cross-process
  `StoreScopedTimerMutationLock`;
- the lock is acquired before a new `ModelContext` is created;
- baseline capture reads the complete, uncapped canonical workspace;
- Apply re-captures that complete workspace inside the lock and requires exact
  equality with the reviewed `AITaskAtomicMutationBaseline`;
- validation and every model mutation use that same fresh context;
- the outer `performAtomicMutation(author: .localMutation)` performs exactly
  one final save, and any validation, checkpoint, operation, or save failure
  rolls the whole context back;
- no SwiftData model or `ModelContext` crosses an isolation boundary; only the
  existing `Sendable` baseline, plan, outcome, and error values do;
- refresh, selection, presentation, and post-commit event publication remain on
  `MainActor` and occur only after the worker reports a successful commit.

## Evidence from the current code

The current coordinator is explicitly `@MainActor`. Both
`captureBaseline()` and `apply(_:)` synchronously acquire the store lock, create
a context, fetch every relevant entity, canonicalize and fingerprint the full
workspace, and (for Apply) validate and mutate it before returning. Therefore
making the facade method merely `async` or wrapping the call in `Task {}` would
not move any work: an unstructured task inherits `MainActor`.

SwiftData does not require the shared `ModelContainer` to stay on MainActor.
The Xcode 27 SwiftData interface declares `ModelContainer` as
`@unchecked Sendable`, and the repository already uses dedicated `@ModelActor`
workers for persistent-history and system-surface reads. The unsafe part would
be sharing a context or its models. This design creates the context only after
the lock is held, uses it synchronously in one isolation domain, and destroys it
before returning.

The actual compile-time barrier is project isolation:

- `StoreScopedTimerMutationTransaction`, `TimerModelContextFactory`, and the
  `ModelContext` atomic-mutation extension are `@MainActor`;
- `SwiftDataTaskRepository`, `SwiftDataTimeTrackingRepository`, and
  `SwiftDataPomodoroRepository` are `@MainActor`;
- recurrence/quantity persistence helpers reached by AI task progress changes
  are `@MainActor`;
- otherwise-pure AI capture/overlay and task-persistence policies still contain
  explicit or default MainActor annotations;
- `ModelContextMutationState.depthByContext` is a mutable MainActor global.

Moving only the top-level coordinator would consequently either fail to compile
or tempt an unsafe `MainActor.run`/`assumeIsolated` escape hatch that moves the
same expensive work back to the UI executor.

## Recommended minimum safe architecture

### 1. Make the existing coordinator the persistence actor

Convert `StoreScopedAITaskAtomicMutationCoordinator` into an `actor` (or add a
private actor executor and leave a very thin facade wrapper). Prefer converting
the existing type unless call-site compatibility proves materially cheaper with
a wrapper. Its immutable initialization payload is:

- `ModelContainer`;
- a pre-resolved `TimerStoreScope`;
- `StoreWriteAuthorization`;
- device ID;
- `@Sendable` clock and checkpoint closures.

Resolve `TimerStoreScope(container:)` on MainActor before actor construction.
This preserves the existing in-memory-container identity registry without
making that weak registry concurrently mutable. Persistent and in-memory
callers then pass the resulting `Sendable` scope into the actor.

Expose actor-isolated, synchronous methods:

```swift
actor StoreScopedAITaskAtomicMutationCoordinator {
    func captureBaseline() throws -> AITaskAtomicMutationBaseline
    func apply(_ plan: AITaskAtomicMutationPlan) throws
        -> AITaskAtomicMutationOutcome
}
```

An external caller uses `try await`, but the method bodies contain no `await`.
That distinction is essential: after the actor begins the lock/CAS/commit
section, actor reentrancy cannot interleave a second request and no lock is ever
held across suspension.

### 2. Keep the existing shared transaction boundary

Make `TimerModelContextFactory` and
`StoreScopedTimerMutationTransaction` `nonisolated` synchronous types rather
than duplicating their six-line protocol inside an AI-only worker. Here,
`nonisolated` means “execute on the caller's current isolation domain”; it does
not mean “share a context concurrently.” The actor constructs the transaction
inside its method and the transaction continues to do this exact sequence:

```text
store-scoped lock
  -> create fresh ModelContext
  -> disable autosave
  -> complete capture/CAS/validation/mutation
  -> one performAtomicMutation save or rollback
  -> release context
store-scoped unlock
```

Do not make `ModelContext`, a repository instance, or any fetched model an
actor property. The context remains a closure-local value. Do not await an
`@ModelActor` created inside the lock: that would hold a blocking file lock
across suspension and would also invert the required fresh-context ordering.

### 3. Make atomic save nesting executor-neutral and synchronized

Replace the MainActor-owned global depth dictionary in
`ModelContext+AtomicMutation.swift` with a small `Mutex`-protected registry.
Only the begin/end/depth bookkeeping is held under the mutex; user operations,
`save()`, and `rollback()` must run after the mutex is released. Then mark the
synchronous `ModelContext` extension `nonisolated`, so every call executes on
the context owner's current actor.

The intended properties are:

- the dictionary is safe when MainActor and the AI persistence actor operate on
  different contexts concurrently;
- a nested repository `saveAfterMutationStep()` still sees the outer depth and
  defers its save;
- the outer boundary removes its entry in `defer`, preventing identifier reuse
  from inheriting stale depth;
- no mutex is held across `await`, file locking, model fetch, save, or rollback.

Do not replace this with `nonisolated(unsafe)` or an unlocked global.

### 4. Generalize the synchronous persistence graph; do not clone it

The repositories involved are context-scoped synchronous objects. Make the
minimum compile-reported graph executor-neutral by declaring the concrete
repository types and their synchronous protocols/helpers `nonisolated`. Keep
the repository classes non-`Sendable`; construct and consume each instance in
the actor method that owns its fresh context. This lets the compiler reject an
attempt to send a repository across actors while allowing the same tested
implementation to run from either MainActor or the AI persistence actor.

The initial graph to audit is:

- `SwiftDataTaskRepository` and `TaskRepository`;
- `SwiftDataTimeTrackingRepository` / `TimeTrackingRepository` and
  `SwiftDataPomodoroRepository` / `PomodoroRepository`, used by archive
  admission;
- `TaskDraftProgressMutationService`, quantity-goal mutation helpers,
  `TaskRecurrencePersistenceState`, and the context-taking recurrence mutation
  methods used by task progress updates;
- pure validation/canonicalization helpers reached from that graph, including
  `AITaskWorkspaceCapture.init`, `AITaskWorkspaceOverlay`,
  `TaskPersistencePolicy`, logical-winner extensions, and hierarchy policies.

Apply `nonisolated` only to code that is synchronous and either pure or operates
on a caller-owned context. UI, observable store state, presentation, and any
method that actually owns MainActor state must remain `@MainActor`. Do not mark
repository classes `@unchecked Sendable`; their lack of Sendable conformance is
part of the safety boundary.

This annotation migration is safer and smaller semantically than introducing
an AI-only repository. A duplicate implementation of create/update/archive,
hierarchy repair, category assignment, quantity goals, and recurrence would
immediately create two persistence contracts and is a future correctness bug.

### 5. Keep authorization and cancellation semantics explicit

Make `StoreWriteAuthorization` and the read-only AppCloudSync safety query
executor-neutral, or resolve a typed `Sendable` authorization decision
immediately before dispatch. The stronger choice is an executor-neutral check
performed by the actor immediately before it acquires the store lock, because
`AppDefaults` documents its `UserDefaults` backing as thread-safe. Avoid a hop
to MainActor from inside the locked section.

Check cancellation before attempting the lock and again immediately after the
lock is acquired but before a context or mutation is created. Once CAS/mutation
begins, do not insert cancellation checks between operations: cancellation is
cooperative and must not weaken the all-or-nothing commit. A cancellation that
arrives after mutation begins is observed only after the atomic operation has
finished.

The existing file lock performs a bounded synchronous wait. That is retained
because it is the accepted cross-process writer boundary. The actor removes the
wait from MainActor; it must not be replaced by a semaphore or by a second lock
domain.

### 6. Make only the UI boundary async

Change these facade surfaces to `async`:

- `captureAITaskWorkspaceBaseline()`;
- `applyAITaskWorkspaceReview(_:)`;
- the generator's `onApply` closure.

The `TimeTrackerStore` remains MainActor-isolated. It snapshots the container,
scope, device ID, reviewed `Sendable` plan, and authorization input, awaits the
persistence actor, then resumes on MainActor to run
`finishStoreScopedMutation`, refresh a no-op result, update selection/routes,
and publish an error. No observable store value is captured by the worker.

The generator owns an Apply task (as it already owns generation work), disables
duplicate Apply while it is active, and handles the result on MainActor. Dismiss
only after `.applied`; workspace conflicts and failures retain the review.

## Exact safety shape of Apply

The actor's Apply method should retain the following ordering without an
intervening suspension:

```text
authorization check
store scope already resolved
acquire shared StoreScopedTimerMutationLock
  cancellation check before mutation
  create fresh context; autosave = false
  performAtomicMutation(author: .localMutation)
    capture the complete current baseline
    require current == reviewed baseline (full CAS)
    replay and validate every reviewed operation
    validate identity collisions and archive admission
    apply the exact reviewed operations
    execute injected checkpoints
    return outcome
  final save succeeds OR outer primitive rolls back
release context
release store lock
return Sendable outcome
MainActor publishes refresh/events/selection
```

Capture uses the same actor and lock/fresh-context sequence but the read-only
transaction path and no save.

## Compile and migration risks

1. **Default actor isolation is MainActor.** The app target sets
   `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so unannotated helper enums and
   extensions may still cause hops/errors after the obvious type annotations
   are removed. Let compiler diagnostics enumerate the transitive graph; do not
   silence them with `@preconcurrency`, `nonisolated(unsafe)`, or
   `MainActor.assumeIsolated`.
2. **Protocol isolation can re-impose MainActor.** Repository protocols and
   protocol extensions must have the same executor-neutral contract as the
   concrete classes. A nonisolated class conforming to a default-MainActor
   protocol will not produce the intended boundary.
3. **Closure Sendability.** The injected time/checkpoint/context-factory
   closures must be `@Sendable` if stored by or transferred into the actor.
   Existing test fault injectors may need `Mutex`-protected state rather than a
   captured mutable variable.
4. **Progress/recurrence cascade.** `TaskDraftProgressMutationService` calls
   context-taking recurrence methods that coexist with methods which create
   their own store transaction. Migrate the synchronous persistence family
   coherently; never bounce just the nested call to MainActor.
5. **Pure types with localized errors.** `AppStrings` is already nonisolated,
   so error descriptions can stay available off-main, but error/policy enums
   under the app's default isolation may need explicit `nonisolated`.
6. **ModelContext depth tracking.** A lock-protected global registry must never
   retain a stale depth after a throw. Preserve the existing `defer` restoration
   and test nested and independent contexts concurrently.
7. **Actor lifetime/configuration.** If the facade caches an executor, replace
   it whenever `ModelContainer` changes. The lower-risk first implementation is
   an immutable per-call actor initialized from the current container/scope;
   the store-scoped file lock, not actor identity, is the serialization source
   of truth.
8. **No-op Apply.** It still performs full fresh CAS and validation. Publication
   stays on MainActor and retains the existing targeted refresh behavior.
9. **Cancellation after commit.** UI code must not translate a successfully
   committed operation into a displayed cancellation merely because its waiter
   was cancelled. Return/record the commit outcome before deciding presentation.
10. **Performance signposts.** Keep the existing signposts around the actor work,
    not around only the MainActor dispatch/await, so a follow-up Release trace
    measures the real capture and atomic Apply intervals.

## Suggested implementation sequence

1. Add permanent command-boundary tests for full baseline capture, successful
   mixed Apply, exact stale-CAS rejection, operation/checkpoint rollback, final
   save rollback, protected identity, active-work archive rejection, and
   nested-save single-commit behavior. Record each oracle in the active
   implementation memory before changing code.
2. Make `ModelContext` atomic nesting and the shared store transaction
   executor-neutral; run the existing store-lock and atomic-mutation suites.
3. Make pure AI capture/overlay/policy types explicitly nonisolated.
4. Convert the coordinator to the actor and compile. Migrate only the
   compiler-identified synchronous repository/progress graph to the same
   caller-owned isolation contract.
5. Change facade and SwiftUI Apply/capture call sites to await the actor while
   keeping state publication on MainActor.
6. Run targeted correctness tests, the seeded Release trace, then the full
   default test/build/format/localization gates. Remove the temporary
   `TEST-SCAFFOLD` performance test after evidence is recorded.

## Rejected alternatives

- `Task {}` or an `async` MainActor method: suspends but does not leave
  MainActor.
- `Task.detached`: discards priority/task-local context and encourages sending
  non-Sendable persistence objects across a boundary.
- `DispatchQueue.global`: bypasses Swift actor isolation and adds a second
  scheduling model.
- a macro `@ModelActor` that uses its automatically created context: that
  context exists before the store lock, violating the accepted fresh-after-lock
  transaction order.
- constructing a `@ModelActor` under the lock and awaiting it: holds a blocking
  lock across suspension and permits reentrancy/deadlock.
- moving only fingerprinting/canonicalization: leaves complete SwiftData fetch,
  validation, and mutation on MainActor and does not satisfy the measured path.
- an AI-only repository or direct model mutation clone: duplicates hierarchy,
  LWW, recurrence, quantity, and archive contracts.
- `MainActor.run`, `assumeIsolated`, `@preconcurrency`, or
  `nonisolated(unsafe)`: either moves the work back to the UI or hides the data
  race from the compiler.
- truncating the workspace, weakening baseline equality, chunk-saving, or
  releasing the lock between capture and mutation: all violate accepted product
  and data-safety contracts.

## Recommendation

Proceed only if the Release evidence confirms an interaction-scale stall. If it
does, use the actor plus executor-neutral shared persistence substrate above.
It is the smallest design that genuinely removes the whole SwiftData path from
MainActor while preserving one lock, a context created after that lock, complete
CAS, and one atomic save/rollback. The implementation should be rejected if it
introduces any actor hop or `await` between lock acquisition and context release.
