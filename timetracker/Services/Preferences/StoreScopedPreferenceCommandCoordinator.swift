import SwiftData

/// Serializes synced preference writes with every other store writer. Settings
/// scenes must not resolve logical preference rows from a stale ModelContext,
/// because timer admission and other commands read those rows under the shared
/// store lock.
@MainActor
struct StoreScopedPreferenceCommandCoordinator {
    let container: ModelContainer
    let writeAuthorization: StoreWriteAuthorization

    init(
        container: ModelContainer,
        writeAuthorization: StoreWriteAuthorization = .applicationState
    ) {
        self.container = container
        self.writeAuthorization = writeAuthorization
    }

    func set(key: AppPreferenceKey, valueJSON: String) throws {
        try set(values: [(key, valueJSON)])
    }

    func set(values: [(AppPreferenceKey, String)]) throws {
        try set(values: values, applyingLocalMutation: {})
    }

    /// Couples an infrequent, device-local setting mutation with the synced
    /// preference commit. The caller must keep this action synchronous and
    /// side-effect free outside the local device (for example, a Keychain
    /// write); network, UI, and projection work remain outside the lock.
    func set(
        values: [(AppPreferenceKey, String)],
        applyingLocalMutation: () throws -> Void
    ) throws {
        try withFreshMutationContext { context in
            try applyingLocalMutation()
            try PreferenceCommandHandler().set(values: values, context: context)
        }
    }

    /// Serializes a device-local setting that has no SwiftData row, such as
    /// the device-only LLM credential, with a concurrent full configuration
    /// save. It deliberately creates a fresh read context without saving it.
    func withLockedStoreAccess(_ operation: () throws -> Void) throws {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )
        try transaction.withFreshReadContext { _ in
            try operation()
        }
    }

    private func withFreshMutationContext(
        _ operation: (ModelContext) throws -> Void
    ) throws {
        try writeAuthorization.requireUserWritesAllowed()
        let scope = try TimerStoreScope(container: container)
        let transaction = StoreScopedTimerMutationTransaction(
            scope: scope,
            container: container
        )
        try transaction.withFreshContext(operation)
    }
}
