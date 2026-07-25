import Darwin
import Foundation

/// `lockf` coordinates the app, widgets, and Shortcuts processes. A recursive
/// in-process lock is also necessary because POSIX record locks are associated
/// with the process and state helpers deliberately nest locked transactions.
private final nonisolated class SyncConflictProcessFileLock: @unchecked Sendable {
    private let recursiveLock = NSRecursiveLock()
    private var depth = 0
    private var descriptor: Int32 = -1

    func withExclusiveAccess<Result>(
        lockURL: URL,
        _ operation: () throws -> Result
    ) throws -> Result {
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
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = lockURL.path.withCString { path in
            Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        // Bounded non-blocking acquire: never hang the caller (often the main
        // thread) on a lock held by a widget or Shortcuts process.
        let deadline = Date().addingTimeInterval(Self.acquireTimeout)
        var backoff = Self.initialBackoff
        while Darwin.lockf(descriptor, F_TLOCK, 0) != 0 {
            let errorCode = errno
            if errorCode == EINTR {
                continue
            }
            guard errorCode == EAGAIN || errorCode == EACCES else {
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

    private static let acquireTimeout: TimeInterval = 5
    private static let initialBackoff: useconds_t = 25000
    private static let maximumBackoff: useconds_t = 250_000

    private static func releaseDescriptor(_ descriptor: Int32) {
        guard descriptor >= 0 else { return }
        while Darwin.lockf(descriptor, F_ULOCK, 0) != 0, errno == EINTR {}
        Darwin.close(descriptor)
    }
}

private final nonisolated class SyncConflictFileLockRegistry: @unchecked Sendable {
    static let shared = SyncConflictFileLockRegistry()

    private let registryLock = NSLock()
    private var locksByPath: [String: SyncConflictProcessFileLock] = [:]

    func lock(for url: URL) -> SyncConflictProcessFileLock {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = locksByPath[url.path] {
            return existing
        }
        let created = SyncConflictProcessFileLock()
        locksByPath[url.path] = created
        return created
    }
}

extension SyncConflictService {
    nonisolated func withExclusiveStateAccess<Result>(
        _ operation: () throws -> Result
    ) throws -> Result {
        let lockURL = try stateLockURL()
        return try SyncConflictFileLockRegistry.shared
            .lock(for: lockURL)
            .withExclusiveAccess(lockURL: lockURL, operation)
    }

    nonisolated static func removeDefaultState() throws {
        let stateURL = try defaultStateURL()
        let backupURL = try defaultPendingForcedUploadSnapshotURL()
        let lockURL = stateLockURL(for: stateURL)
        let durableRootURL = stateURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let durableFile = DurableLocalFile()
        try SyncConflictFileLockRegistry.shared
            .lock(for: lockURL)
            .withExclusiveAccess(lockURL: lockURL) {
                // If interrupted, a still-present authoritative state remains
                // preferable to an orphaned recovery mirror. Each removal is
                // durably published before proceeding to the next file.
                try durableFile.removeIfPresent(
                    at: backupURL,
                    durableRootURL: durableRootURL
                )
                try durableFile.removeIfPresent(
                    at: stateURL,
                    durableRootURL: durableRootURL
                )
                for snapshotURL in SyncConflictService.allConflictSnapshotSlotURLs(for: stateURL) {
                    try durableFile.removeIfPresent(
                        at: snapshotURL,
                        durableRootURL: durableRootURL
                    )
                }
            }
    }
}
