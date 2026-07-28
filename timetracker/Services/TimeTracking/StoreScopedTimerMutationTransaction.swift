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

/// Shared transaction boundary for coordinated store reads and writes. The
/// fresh context is created only after the store lock is held, so it cannot
/// carry a stale snapshot into the critical section.
///
/// Ordinary timer commands, task lifecycle writes, Pomodoro phase commands,
/// ledger record editing/deletion, and sync snapshot work use this lock domain.
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
        author: TimeTrackerHistoryAuthor,
        _ operation: (ModelContext) throws -> Result
    ) throws -> Result {
        try withFreshReadContext { context in
            try context.performAtomicMutation(author: author) {
                try operation(context)
            }
        }
    }

    /// Holds the store lock around a fresh read context without saving it.
    /// Snapshot capture uses this path so a read cannot manufacture a CloudKit
    /// export or commit accidental changes.
    func withFreshReadContext<Result>(
        _ operation: (ModelContext) throws -> Result
    ) throws -> Result {
        try mutationLock.withExclusiveAccess(for: scope) {
            let context = try contextFactory.makeFreshContext()
            context.autosaveEnabled = false
            return try operation(context)
        }
    }
}
