import Foundation

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

    init(persistentStoreURL: URL) {
        storage = .persistent(Self.canonicalStoreURL(persistentStoreURL))
    }

    init(inMemoryIdentity: UUID) {
        storage = .inMemory(inMemoryIdentity)
    }

    var persistentStoreURL: URL? {
        guard case .persistent(let storeURL) = storage else { return nil }
        return storeURL
    }

    var mutationLockURL: URL {
        switch storage {
        case .persistent(let storeURL):
            return storeURL.deletingLastPathComponent().appendingPathComponent(
                storeURL.lastPathComponent + StoreScopedTimerMutationLock.fileSuffix
            )
        case .inMemory(let identity):
            return FileManager.default.temporaryDirectory.appendingPathComponent(
                "timetracker-\(identity.uuidString.lowercased())"
                    + StoreScopedTimerMutationLock.fileSuffix
            )
        }
    }

    private static func canonicalStoreURL(_ url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        var cursor = standardizedURL
        var missingComponents: [String] = []

        while FileManager.default.fileExists(atPath: cursor.path) == false,
              cursor.pathComponents.count > 1 {
            missingComponents.insert(cursor.lastPathComponent, at: 0)
            cursor.deleteLastPathComponent()
        }

        var canonicalURL = cursor.resolvingSymlinksInPath().standardizedFileURL
        for component in missingComponents {
            canonicalURL.appendPathComponent(component)
        }
        return canonicalURL.standardizedFileURL
    }
}
