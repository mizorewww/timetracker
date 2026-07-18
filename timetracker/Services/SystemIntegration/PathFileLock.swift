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

        while flock(descriptor, LOCK_EX) != 0 {
            let errorCode = errno
            if errorCode == EINTR { continue }
            Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
        return descriptor
    }

    private static func releaseDescriptor(_ descriptor: Int32) {
        guard descriptor >= 0 else { return }
        while flock(descriptor, LOCK_UN) != 0, errno == EINTR {}
        Darwin.close(descriptor)
    }
}

nonisolated final class PathFileLockRegistry: @unchecked Sendable {
    static let shared = PathFileLockRegistry()

    private let registryLock = NSLock()
    private let locksByPath = NSMapTable<NSString, PathProcessFileLock>(
        keyOptions: .copyIn,
        valueOptions: .weakMemory
    )

    func lock(for url: URL) -> PathProcessFileLock {
        let canonicalURL = canonicalLockURL(for: url)
        let path = canonicalURL.path
        registryLock.lock()
        defer { registryLock.unlock() }
        let key = path as NSString
        if let existing = locksByPath.object(forKey: key) {
            return existing
        }
        let created = PathProcessFileLock(lockURL: canonicalURL)
        locksByPath.setObject(created, forKey: key)
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
