import Foundation

nonisolated enum DurableLocalFileFaultPoint: String, Sendable {
    case beforeDirectoryCreation
    case afterDirectoryCreationBeforeParentSync
    case afterAtomicWriteBeforeFileSync
    case afterFileSyncBeforeDirectorySync
    case afterRemovalBeforeDirectorySync
    case beforeQuarantinePruning
    case afterQuarantinePruningBeforeDirectorySync
    case afterQuarantineMoveBeforeFileSync
}

nonisolated enum DurableLocalFileError: Error, Equatable, Sendable {
    case durableRootUnavailable
    case durableRootIsNotAncestor
    case symbolicLinkNotAllowed
    case managedPathIsNotRegularFile
    case reservedLockPath
    case quarantineRollbackFailed(canonicalPath: String, quarantinePath: String)
    case invalidQuarantinePrefix
    case quarantineEntryMetadataUnavailable
}

nonisolated struct DurableLocalFile {
    static let lockFileName = ".TimeTrackerDurable.lock"

    typealias FaultInjector = (DurableLocalFileFaultPoint) throws -> Void
    typealias DirectorySynchronizer = (URL) throws -> Void

    let fileManager: FileManager
    let quarantinePolicy: DurableLocalFileQuarantinePolicy
    let dateProvider: () -> Date
    let directorySynchronizer: DirectorySynchronizer?
    let injectFault: FaultInjector

    init(
        fileManager: FileManager = .default,
        quarantinePolicy: DurableLocalFileQuarantinePolicy = .production,
        dateProvider: @escaping () -> Date = Date.init,
        directorySynchronizer: DirectorySynchronizer? = nil,
        injectFault: @escaping FaultInjector = { _ in }
    ) {
        self.fileManager = fileManager
        self.quarantinePolicy = quarantinePolicy
        self.dateProvider = dateProvider
        self.directorySynchronizer = directorySynchronizer
        self.injectFault = injectFault
    }

    /// Compatibility path for files whose nearest existing ancestor is known
    /// to be durable when this call begins. Recovery-critical callers must use
    /// the explicit durable-root overload so an interrupted `mkdir` can be
    /// repaired on retry.
    func write(
        _ data: Data,
        to url: URL,
        excludeFromBackup: Bool = false
    ) throws {
        let directoryURL = url.deletingLastPathComponent()
        try write(
            data,
            to: url,
            durableRootURL: nearestExistingDirectory(atOrAbove: directoryURL),
            excludeFromBackup: excludeFromBackup
        )
    }

    func write(
        _ data: Data,
        to url: URL,
        durableRootURL: URL,
        excludeFromBackup: Bool = false
    ) throws {
        let paths = try canonicalManagedPaths(at: url, through: durableRootURL)
        let standardizedRoot = paths.root
        let standardizedURL = paths.url
        try rejectReservedLockPath(standardizedURL, durableRootURL: standardizedRoot)
        try withExclusiveAccess(through: standardizedRoot) {
            try writeWithExclusiveAccess(
                data,
                to: standardizedURL,
                durableRootURL: standardizedRoot,
                excludeFromBackup: excludeFromBackup
            )
        }
    }

    func removeIfPresent(at url: URL) throws {
        let directoryURL = url.deletingLastPathComponent()
        try removeIfPresent(
            at: url,
            durableRootURL: nearestExistingDirectory(atOrAbove: directoryURL)
        )
    }

    func removeIfPresent(at url: URL, durableRootURL: URL) throws {
        let paths = try canonicalManagedPaths(at: url, through: durableRootURL)
        let standardizedRoot = paths.root
        let standardizedURL = paths.url
        try rejectReservedLockPath(standardizedURL, durableRootURL: standardizedRoot)
        try withExclusiveAccess(through: standardizedRoot) {
            try removeWithExclusiveAccess(
                at: standardizedURL,
                durableRootURL: standardizedRoot
            )
        }
    }

    func withExclusiveAccess<Result>(
        through durableRootURL: URL,
        _ operation: () throws -> Result
    ) throws -> Result {
        let lockURL = durableRootURL.appendingPathComponent(Self.lockFileName)
        return try PathFileLockRegistry.shared.lock(for: lockURL)
            .withExclusiveAccess(operation)
    }
}
