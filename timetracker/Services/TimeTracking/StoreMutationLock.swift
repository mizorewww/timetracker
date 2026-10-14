import Foundation

/// Serializes timer read-plan-write transactions for one store, including
/// mutations arriving from other app, widget, and Shortcuts processes.
nonisolated struct StoreMutationLock: Sendable {
    static let fileSuffix = ".store-mutations.lock"

    func withExclusiveAccess<Result>(
        for scope: StoreScope,
        _ operation: () throws -> Result
    ) throws -> Result {
        try PathFileLockRegistry.shared
            .lock(for: scope.mutationLockURL)
            .withExclusiveAccess(operation)
    }
}
