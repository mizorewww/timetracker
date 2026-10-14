import SwiftData

/// Shared transaction boundary for coordinated store reads and writes. The
/// fresh context is created only after the store lock is held, so it cannot
/// carry a stale snapshot into the critical section.
///
/// Ordinary timer commands, task lifecycle writes, Pomodoro phase commands,
/// ledger record editing/deletion, and sync snapshot work use this lock domain.
nonisolated struct StoreMutationTransaction {
    let scope: StoreScope
    let container: ModelContainer
    let mutationLock: StoreMutationLock

    init(
        scope: StoreScope,
        container: ModelContainer,
        mutationLock: StoreMutationLock = .init()
    ) {
        self.scope = scope
        self.container = container
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
            let context = ModelContext(container)
            context.autosaveEnabled = false
            return try operation(context)
        }
    }
}
