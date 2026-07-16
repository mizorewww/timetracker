import SwiftData

@MainActor
struct TimerModelContextFactory {
    private let makeContext: () throws -> ModelContext

    init(container: ModelContainer) {
        makeContext = { ModelContext(container) }
    }

    init(makeContext: @escaping () throws -> ModelContext) {
        self.makeContext = makeContext
    }

    func makeFreshContext() throws -> ModelContext {
        try makeContext()
    }
}

/// Foundation for the future timer coordinator. The fresh context is created
/// only after the store lock is held, so it cannot carry a stale active-segment
/// snapshot into the critical section.
///
/// This type is deliberately not wired to any timer writer yet. The existing
/// multi-writer admission race remains until every writer enters one coordinator.
@MainActor
struct StoreScopedTimerMutationTransaction {
    let scope: TimerStoreScope
    let contextFactory: TimerModelContextFactory
    let mutationLock: StoreScopedTimerMutationLock

    init(
        scope: TimerStoreScope,
        container: ModelContainer,
        mutationLock: StoreScopedTimerMutationLock = .init()
    ) {
        self.init(
            scope: scope,
            contextFactory: TimerModelContextFactory(container: container),
            mutationLock: mutationLock
        )
    }

    init(
        scope: TimerStoreScope,
        contextFactory: TimerModelContextFactory,
        mutationLock: StoreScopedTimerMutationLock = .init()
    ) {
        self.scope = scope
        self.contextFactory = contextFactory
        self.mutationLock = mutationLock
    }

    func withFreshContext<Result>(
        _ operation: (ModelContext) throws -> Result
    ) throws -> Result {
        try mutationLock.withExclusiveAccess(for: scope) {
            let context = try contextFactory.makeFreshContext()
            context.autosaveEnabled = false
            return try context.performAtomicMutation {
                try operation(context)
            }
        }
    }
}
