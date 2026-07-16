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

/// Transaction boundary used by the timer coordinator. The fresh context is
/// created only after the store lock is held, so it cannot carry a stale
/// active-segment snapshot into the critical section.
///
/// Ordinary timer commands, task lifecycle writes, and Pomodoro phase commands
/// use this boundary. Ledger record editing/deletion and snapshot restoration
/// still require their own store-scoped coordination before every related
/// writer shares this lock domain.
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
