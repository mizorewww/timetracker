import Darwin
import Foundation

/// A cross-process exclusive `flock` on one lock file, recursive within the
/// process so nested access by the same owner does not self-block.
final nonisolated class PathProcessFileLock: @unchecked Sendable {
    /// Widget and Shortcuts processes share these lock files. Waiting forever
    /// would freeze the caller (usually the main thread), so acquisition
    /// retries with short backoff for about a second and then fails; every
    /// critical section is a short local SwiftData transaction.
    static let acquireTimeout: Duration = .seconds(1)
    private static let initialBackoff: useconds_t = 10000
    private static let maximumBackoff: useconds_t = 100_000

    private let lockURL: URL
    private let recursiveLock = NSRecursiveLock()
    private var depth = 0
    private var descriptor: Int32 = -1

    init(lockURL: URL) {
        self.lockURL = lockURL
    }

    func withExclusiveAccess<Result>(_ operation: () throws -> Result) throws -> Result {
        recursiveLock.lock()
        defer { recursiveLock.unlock() }

        if depth == 0 {
            descriptor = try Self.acquireDescriptor(lockURL: lockURL)
        }
        depth += 1
        defer {
            depth -= 1
            if depth == 0 {
                while flock(descriptor, LOCK_UN) != 0, errno == EINTR {}
                Darwin.close(descriptor)
                descriptor = -1
            }
        }
        return try operation()
    }

    private static func acquireDescriptor(lockURL: URL) throws -> Int32 {
        let descriptor = lockURL.path.withCString { path in
            Darwin.open(
                path,
                O_CREAT | O_RDWR | O_CLOEXEC | O_CLOFORK | O_NOFOLLOW_ANY,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        // ContinuousClock: a wall-clock change must not stretch or cut the wait.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: acquireTimeout)
        var backoff = initialBackoff
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let errorCode = errno
            if errorCode == EINTR {
                continue
            }
            guard errorCode == EWOULDBLOCK, clock.now < deadline else {
                Darwin.close(descriptor)
                throw POSIXError(errorCode == EWOULDBLOCK ? .ETIMEDOUT : POSIXErrorCode(rawValue: errorCode) ?? .EIO)
            }
            usleep(backoff)
            backoff = min(backoff * 2, maximumBackoff)
        }
        return descriptor
    }
}

/// One lock instance per canonical path while any caller uses it, so aliases
/// of the same file share the in-process recursion state. An entry is dropped
/// once its last user returns, so short-lived (for example in-memory test)
/// stores do not accumulate locks for the life of the process.
final nonisolated class PathFileLockRegistry: @unchecked Sendable {
    static let shared = PathFileLockRegistry()

    private let registryLock = NSLock()
    private var entriesByPath: [String: (lock: PathProcessFileLock, users: Int)] = [:]

    func withExclusiveAccess<Result>(
        to url: URL,
        _ operation: () throws -> Result
    ) throws -> Result {
        let standardizedURL = url.standardizedFileURL
        let canonicalURL = CanonicalFileURL
            .resolvingExistingAncestor(of: standardizedURL.deletingLastPathComponent())
            .appendingPathComponent(standardizedURL.lastPathComponent)
        let lock = retainLock(for: canonicalURL)
        defer { releaseLock(for: canonicalURL.path) }
        return try lock.withExclusiveAccess(operation)
    }

    private func retainLock(for canonicalURL: URL) -> PathProcessFileLock {
        registryLock.lock()
        defer { registryLock.unlock() }
        let path = canonicalURL.path
        let lock = entriesByPath[path]?.lock ?? PathProcessFileLock(lockURL: canonicalURL)
        entriesByPath[path] = (lock, (entriesByPath[path]?.users ?? 0) + 1)
        return lock
    }

    private func releaseLock(for path: String) {
        registryLock.lock()
        defer { registryLock.unlock() }
        guard let entry = entriesByPath[path] else { return }
        if entry.users <= 1 {
            entriesByPath.removeValue(forKey: path)
        } else {
            entriesByPath[path] = (entry.lock, entry.users - 1)
        }
    }
}
