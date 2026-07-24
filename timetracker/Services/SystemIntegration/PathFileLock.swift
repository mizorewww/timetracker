import Darwin
import Foundation

/// `flock` coordinates open descriptions across processes and path aliases.
/// A recursive in-process lock keeps same-owner nested access from self-blocking.
nonisolated final class PathProcessFileLock: @unchecked Sendable {
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
                Self.releaseDescriptor(descriptor)
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

        // Widget and Shortcuts processes share this lock domain. A permanently
        // blocked wait freezes the caller (often the main thread), so retry
        // with backoff for a bounded budget and fail instead of hanging.
        let deadline = Date().addingTimeInterval(Self.acquireTimeout)
        var backoff = Self.initialBackoff
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let errorCode = errno
            if errorCode == EINTR { continue }
            guard errorCode == EWOULDBLOCK else {
                Darwin.close(descriptor)
                throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
            }
            guard Date() < deadline else {
                Darwin.close(descriptor)
                throw POSIXError(.ETIMEDOUT)
            }
            usleep(backoff)
            backoff = min(backoff * 2, Self.maximumBackoff)
        }
        return descriptor
    }

    static var acquireTimeout: TimeInterval = 5
    private static let initialBackoff: useconds_t = 25_000
    private static let maximumBackoff: useconds_t = 250_000

    private static func releaseDescriptor(_ descriptor: Int32) {
        guard descriptor >= 0 else { return }
        while flock(descriptor, LOCK_UN) != 0, errno == EINTR {}
        Darwin.close(descriptor)
    }
}

nonisolated final class PathFileLockRegistry: @unchecked Sendable {
    static let shared = PathFileLockRegistry()

    private let registryLock = NSLock()
    // Strong references: a weak table can drop a lock instance mid-flight and
    // hand the same path a second guard, defeating in-process recursion safety.
    private var locksByPath: [String: PathProcessFileLock] = [:]

    func lock(for url: URL) -> PathProcessFileLock {
        let canonicalURL = canonicalLockURL(for: url)
        let path = canonicalURL.path
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = locksByPath[path] {
            return existing
        }
        let created = PathProcessFileLock(lockURL: canonicalURL)
        locksByPath[path] = created
        return created
    }

    private func canonicalLockURL(for url: URL) -> URL {
        let standardizedURL = url.standardizedFileURL
        let canonicalParent = CanonicalFileURL.resolvingExistingAncestor(
            of: standardizedURL.deletingLastPathComponent()
        )
        return canonicalParent
            .appendingPathComponent(standardizedURL.lastPathComponent)
    }
}
