import Foundation
import SwiftData

nonisolated enum StoreScopeResolutionError: Error, Equatable {
    case missingConfiguration
    case ambiguousConfigurations(Int)
}

/// Resolves each container's scope once for the container's lifetime, so
/// in-memory stores keep one identity and every command skips re-resolving
/// the canonical store path.
@MainActor
private final class StoreScopeCache {
    static let shared = StoreScopeCache()

    private struct Entry {
        weak var container: ModelContainer?
        let scope: StoreScope
    }

    private var entriesByContainerID: [ObjectIdentifier: Entry] = [:]

    func scope(
        for container: ModelContainer,
        resolve: () throws -> StoreScope
    ) rethrows -> StoreScope {
        let containerID = ObjectIdentifier(container)
        if let entry = entriesByContainerID[containerID], entry.container === container {
            return entry.scope
        }
        entriesByContainerID = entriesByContainerID.filter { $0.value.container != nil }
        let scope = try resolve()
        entriesByContainerID[containerID] = Entry(container: container, scope: scope)
        return scope
    }
}

/// Stable identity for every process that can mutate one timer store.
///
/// Persistent stores converge on a canonical file URL. In-memory containers
/// must retain and reuse one explicit identity for their complete lifetime.
nonisolated struct StoreScope: Hashable, Sendable {
    private enum Storage: Hashable, Sendable {
        case persistent(URL)
        case inMemory(UUID)
    }

    private let storage: Storage

    /// Resolves the lock identity from the actual store configuration owned by
    /// this container. Persistent stores use their configured URL directly;
    /// in-memory stores receive an identity scoped to the container's lifetime.
    @MainActor
    init(container: ModelContainer) throws {
        self = try StoreScopeCache.shared.scope(for: container) {
            let configurations = container.configurations
            guard let configuration = configurations.first else {
                throw StoreScopeResolutionError.missingConfiguration
            }
            guard configurations.count == 1 else {
                throw StoreScopeResolutionError.ambiguousConfigurations(
                    configurations.count
                )
            }
            return configuration.isStoredInMemoryOnly
                ? StoreScope(inMemoryIdentity: UUID())
                : StoreScope(persistentStoreURL: configuration.url)
        }
    }

    init(persistentStoreURL: URL) {
        storage = .persistent(Self.canonicalStoreURL(persistentStoreURL))
    }

    init(inMemoryIdentity: UUID) {
        storage = .inMemory(inMemoryIdentity)
    }

    var persistentStoreURL: URL? {
        guard case let .persistent(storeURL) = storage else { return nil }
        return storeURL
    }

    var mutationLockURL: URL {
        switch storage {
        case let .persistent(storeURL):
            storeURL.deletingLastPathComponent().appendingPathComponent(
                storeURL.lastPathComponent + StoreMutationSession.lockFileSuffix
            )
        case let .inMemory(identity):
            FileManager.default.temporaryDirectory.appendingPathComponent(
                "timetracker-\(identity.uuidString.lowercased())"
                    + StoreMutationSession.lockFileSuffix
            )
        }
    }

    private static func canonicalStoreURL(_ url: URL) -> URL {
        CanonicalFileURL.resolvingExistingAncestor(of: url)
    }
}
