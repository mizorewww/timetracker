import Foundation
import SwiftData

nonisolated enum TimerStoreScopeResolutionError: Error, Equatable {
    case missingConfiguration
    case ambiguousConfigurations(Int)
}

@MainActor
private final class InMemoryTimerStoreScopeRegistry {
    static let shared = InMemoryTimerStoreScopeRegistry()

    private final class Entry {
        weak var container: ModelContainer?
        let identity: UUID

        init(container: ModelContainer, identity: UUID = UUID()) {
            self.container = container
            self.identity = identity
        }
    }

    private var entriesByContainerID: [ObjectIdentifier: Entry] = [:]

    func identity(for container: ModelContainer) -> UUID {
        entriesByContainerID = entriesByContainerID.filter {
            $0.value.container != nil
        }

        let containerID = ObjectIdentifier(container)
        if let entry = entriesByContainerID[containerID], entry.container === container {
            return entry.identity
        }

        let entry = Entry(container: container)
        entriesByContainerID[containerID] = entry
        return entry.identity
    }
}

/// Stable identity for every process that can mutate one timer store.
///
/// Persistent stores converge on a canonical file URL. In-memory containers
/// must retain and reuse one explicit identity for their complete lifetime.
nonisolated struct TimerStoreScope: Hashable, Sendable {
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
        let configurations = container.configurations
        guard let configuration = configurations.first else {
            throw TimerStoreScopeResolutionError.missingConfiguration
        }
        guard configurations.count == 1 else {
            throw TimerStoreScopeResolutionError.ambiguousConfigurations(
                configurations.count
            )
        }

        if configuration.isStoredInMemoryOnly {
            self.init(
                inMemoryIdentity: InMemoryTimerStoreScopeRegistry.shared.identity(
                    for: container
                )
            )
        } else {
            self.init(persistentStoreURL: configuration.url)
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
                storeURL.lastPathComponent + StoreScopedTimerMutationLock.fileSuffix
            )
        case let .inMemory(identity):
            FileManager.default.temporaryDirectory.appendingPathComponent(
                "timetracker-\(identity.uuidString.lowercased())"
                    + StoreScopedTimerMutationLock.fileSuffix
            )
        }
    }

    private static func canonicalStoreURL(_ url: URL) -> URL {
        CanonicalFileURL.resolvingExistingAncestor(of: url)
    }
}
