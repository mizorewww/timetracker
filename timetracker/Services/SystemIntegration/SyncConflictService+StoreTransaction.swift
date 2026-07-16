import SwiftData

extension SyncConflictService {
    /// Establishes the only supported ordering for work that touches both the
    /// SwiftData store and durable sync state:
    ///
    ///     store lock -> fresh ModelContext -> sync-state lock
    ///
    /// The operation decides whether its fresh context is read-only or wraps a
    /// restore primitive in `performAtomicMutation`.
    func withLockedFreshStoreContext<Result>(
        context: ModelContext,
        _ operation: (ModelContext) throws -> Result
    ) throws -> Result {
        let container = context.container
        let scope = try TimerStoreScope(container: container)
        return try StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        ).withFreshReadContext(operation)
    }
}
