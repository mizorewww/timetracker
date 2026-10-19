import SwiftData

/// The one store mutation boundary. Every durable store-scoped write
/// authorizes, takes the cross-process store lock (shared with the widget,
/// Shortcuts, and Watch command processes), and runs in a fresh context that
/// is created only after the lock is held, so it cannot carry a stale snapshot
/// into the critical section.
nonisolated struct StoreMutationSession {
    static let lockFileSuffix = ".store-mutations.lock"

    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
    }

    /// Authorizes the write, holds the store lock, and runs the operation in a
    /// fresh context committed with one atomic save.
    @MainActor
    func withFreshMutationContext<Result>(
        author: TimeTrackerHistoryAuthor = .localMutation,
        _ operation: (ModelContext) throws -> Result
    ) throws -> Result {
        try writeAuthorization.requireUserWritesAllowed()
        return try Self.withLockedFreshContext(
            scope: StoreScope(container: container),
            container: container
        ) { context in
            try context.performAtomicMutation(author: author) {
                try operation(context)
            }
        }
    }

    /// Holds the store lock around a fresh context without authorizing or
    /// saving. Snapshot capture uses this path so a read cannot manufacture a
    /// CloudKit export; callers off the main actor that authorize themselves
    /// wrap their own atomic mutation in it.
    static func withLockedFreshContext<Result>(
        scope: StoreScope,
        container: ModelContainer,
        _ operation: (ModelContext) throws -> Result
    ) throws -> Result {
        try PathFileLockRegistry.shared
            .lock(for: scope.mutationLockURL)
            .withExclusiveAccess {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                return try operation(context)
            }
    }
}

/// A store-scoped writer: every coordinator authorizes and locks through the
/// same session built from its container.
protocol StoreScopedCommandCoordinator {
    var container: ModelContainer { get }
    var writeAuthorization: StoreWriteAuthorization { get }
}

extension StoreScopedCommandCoordinator {
    var mutationSession: StoreMutationSession {
        StoreMutationSession(container: container, writeAuthorization: writeAuthorization)
    }
}
