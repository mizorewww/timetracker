import Darwin
import Foundation

nonisolated struct MonotonicFileLockDeadline: Sendable {
    private let clock: ContinuousClock
    private let deadline: ContinuousClock.Instant

    init(timeout: Duration) {
        let clock = ContinuousClock()
        self.clock = clock
        deadline = clock.now.advanced(by: timeout)
    }

    var hasRemainingTime: Bool {
        clock.now < deadline
    }
}

/// The POSIX primitive guarding a lock descriptor.
/// `flock` coordinates open descriptions across processes and path aliases.
/// `lockf` record locks are associated with the process and suit helpers that
/// deliberately nest locked transactions.
nonisolated enum ProcessFileLockMechanism: Sendable {
    case flock
    case lockf

    fileprivate func openDescriptor(lockURL: URL) throws -> Int32 {
        let descriptor: Int32
        switch self {
        case .flock:
            descriptor = lockURL.path.withCString { path in
                Darwin.open(
                    path,
                    O_CREAT | O_RDWR | O_CLOEXEC | O_CLOFORK | O_NOFOLLOW_ANY,
                    S_IRUSR | S_IWUSR
                )
            }
        case .lockf:
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            descriptor = lockURL.path.withCString { path in
                Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            }
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return descriptor
    }

    fileprivate func tryAcquire(_ descriptor: Int32) -> Int32 {
        switch self {
        case .flock:
            flockExclusiveNonBlocking(descriptor)
        case .lockf:
            Darwin.lockf(descriptor, F_TLOCK, 0)
        }
    }

    fileprivate func isContention(_ errorCode: Int32) -> Bool {
        switch self {
        case .flock:
            errorCode == EWOULDBLOCK
        case .lockf:
            errorCode == EAGAIN || errorCode == EACCES
        }
    }

    fileprivate func release(_ descriptor: Int32) {
        switch self {
        case .flock:
            flockUnlock(descriptor)
        case .lockf:
            while Darwin.lockf(descriptor, F_ULOCK, 0) != 0, errno == EINTR {}
        }
    }
}

/// File-scope wrappers: inside `ProcessFileLockMechanism` the `flock` case
/// shadows the C function, and qualified lookup finds the `Darwin.flock` struct.
private func flockExclusiveNonBlocking(_ descriptor: Int32) -> Int32 {
    flock(descriptor, LOCK_EX | LOCK_NB)
}

private func flockUnlock(_ descriptor: Int32) {
    while flock(descriptor, LOCK_UN) != 0, errno == EINTR {}
}

/// A recursive in-process lock keeps same-owner nested access from self-blocking.
final nonisolated class PathProcessFileLock: @unchecked Sendable {
    private let lockURL: URL
    private let mechanism: ProcessFileLockMechanism
    private let recursiveLock = NSRecursiveLock()
    private var depth = 0
    private var descriptor: Int32 = -1

    init(lockURL: URL, mechanism: ProcessFileLockMechanism) {
        self.lockURL = lockURL
        self.mechanism = mechanism
    }

    func withExclusiveAccess<Result>(_ operation: () throws -> Result) throws -> Result {
        recursiveLock.lock()
        defer { recursiveLock.unlock() }

        if depth == 0 {
            descriptor = try Self.acquireDescriptor(
                lockURL: lockURL,
                mechanism: mechanism
            )
        }
        depth += 1
        defer {
            depth -= 1
            if depth == 0 {
                Self.releaseDescriptor(descriptor, mechanism: mechanism)
                descriptor = -1
            }
        }
        return try operation()
    }

    private static func acquireDescriptor(
        lockURL: URL,
        mechanism: ProcessFileLockMechanism
    ) throws -> Int32 {
        let descriptor = try mechanism.openDescriptor(lockURL: lockURL)

        // Widget and Shortcuts processes share these lock domains. A permanently
        // blocked wait freezes the caller (often the main thread), so retry
        // with backoff for a bounded budget and fail instead of hanging.
        let deadline = MonotonicFileLockDeadline(
            timeout: Self.acquireTimeout
        )
        var backoff = Self.initialBackoff
        while mechanism.tryAcquire(descriptor) != 0 {
            let errorCode = errno
            if errorCode == EINTR {
                continue
            }
            guard mechanism.isContention(errorCode) else {
                Darwin.close(descriptor)
                throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
            }
            guard deadline.hasRemainingTime else {
                Darwin.close(descriptor)
                throw POSIXError(.ETIMEDOUT)
            }
            usleep(backoff)
            backoff = min(backoff * 2, Self.maximumBackoff)
        }
        return descriptor
    }

    static var acquireTimeout: Duration = .seconds(5)
    private static let initialBackoff: useconds_t = 25000
    private static let maximumBackoff: useconds_t = 250_000

    private static func releaseDescriptor(
        _ descriptor: Int32,
        mechanism: ProcessFileLockMechanism
    ) {
        guard descriptor >= 0 else { return }
        mechanism.release(descriptor)
        Darwin.close(descriptor)
    }
}

final nonisolated class PathFileLockRegistry: @unchecked Sendable {
    static let shared = PathFileLockRegistry(
        mechanism: .flock,
        canonicalize: { url in
            let standardizedURL = url.standardizedFileURL
            let canonicalParent = CanonicalFileURL.resolvingExistingAncestor(
                of: standardizedURL.deletingLastPathComponent()
            )
            return canonicalParent
                .appendingPathComponent(standardizedURL.lastPathComponent)
        }
    )

    private let mechanism: ProcessFileLockMechanism
    private let canonicalize: (URL) -> URL
    private let registryLock = NSLock()
    /// Strong references: a weak table can drop a lock instance mid-flight and
    /// hand the same path a second guard, defeating in-process recursion safety.
    private var locksByPath: [String: PathProcessFileLock] = [:]

    init(
        mechanism: ProcessFileLockMechanism,
        canonicalize: @escaping (URL) -> URL = { $0 }
    ) {
        self.mechanism = mechanism
        self.canonicalize = canonicalize
    }

    func lock(for url: URL) -> PathProcessFileLock {
        let canonicalURL = canonicalize(url)
        let path = canonicalURL.path
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = locksByPath[path] {
            return existing
        }
        let created = PathProcessFileLock(
            lockURL: canonicalURL,
            mechanism: mechanism
        )
        locksByPath[path] = created
        return created
    }
}
