import SwiftData

/// Serializes synced preference writes with every other store writer. Settings
/// scenes must not resolve logical preference rows from a stale ModelContext,
/// because timer admission and other commands read those rows under the shared
/// store lock.
@MainActor
struct StoreScopedPreferenceCommandCoordinator {
    let session: StoreMutationSession

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

    private func withFreshMutationContext(
        _ operation: (ModelContext) throws -> Void
    ) throws {
        try session.withFreshMutationContext(operation)
    }
}
