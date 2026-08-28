import SwiftData

/// Shared prelude for store-scoped commands: enforces the write policy, then
/// opens the locked fresh-context transaction for the store. Command
/// coordinators keep their domain operation; this type owns only the
/// authorization and lock entry that every coordinator used to repeat.
@MainActor
struct StoreScopedMutationSession {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization

    /// Authorizes the write, holds the store mutation lock, and runs the
    /// operation in a fresh committing sibling context.
    func withFreshMutationContext<Result>(
        author: TimeTrackerHistoryAuthor = .localMutation,
        _ operation: (ModelContext) throws -> Result
    ) throws -> Result {
        try writeAuthorization.requireUserWritesAllowed()
        return try StoreScopedTimerMutationTransaction(
            scope: TimerStoreScope(container: container),
            container: container
        ).withFreshContext(author: author, operation)
    }

    /// Authorizes the write and holds the store lock around a fresh read
    /// context without saving it.
    func withFreshReadContext<Result>(
        _ operation: (ModelContext) throws -> Result
    ) throws -> Result {
        try writeAuthorization.requireUserWritesAllowed()
        return try StoreScopedTimerMutationTransaction(
            scope: TimerStoreScope(container: container),
            container: container
        ).withFreshReadContext(operation)
    }
}
