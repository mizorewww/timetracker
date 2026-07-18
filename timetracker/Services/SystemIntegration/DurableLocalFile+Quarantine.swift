import Foundation

nonisolated struct DurableLocalFileQuarantinePolicy: Equatable, Sendable {
    let maximumFileCount: Int
    let maximumTotalByteCount: Int64
    let maximumAge: TimeInterval

    static let production = Self(
        maximumFileCount: 8,
        maximumTotalByteCount: 16 * 1_024 * 1_024,
        maximumAge: 14 * 24 * 60 * 60
    )

    init(
        maximumFileCount: Int,
        maximumTotalByteCount: Int64,
        maximumAge: TimeInterval
    ) {
        precondition(maximumFileCount >= 0)
        precondition(maximumTotalByteCount >= 0)
        precondition(maximumAge >= 0 && maximumAge.isFinite)
        self.maximumFileCount = maximumFileCount
        self.maximumTotalByteCount = maximumTotalByteCount
        self.maximumAge = maximumAge
    }
}
nonisolated extension DurableLocalFile {
    private static var quarantineDirectoryName: String { ".TimeTrackerQuarantine" }

    func quarantineIfPresent(at url: URL, prefix: String) throws -> URL? {
        let directoryURL = url.deletingLastPathComponent().standardizedFileURL
        return try quarantineIfPresent(
            at: url,
            prefix: prefix,
            durableRootURL: nearestExistingDirectory(atOrAbove: directoryURL)
        )
    }

    func quarantineIfPresent(
        at url: URL,
        prefix: String,
        durableRootURL: URL
    ) throws -> URL? {
        guard prefix.isEmpty == false,
              prefix.utf8.count <= 128,
              prefix.contains("/") == false,
              prefix.contains(":") == false,
              prefix.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw DurableLocalFileError.invalidQuarantinePrefix
        }
        let paths = try canonicalManagedPaths(at: url, through: durableRootURL)
        let standardizedRoot = paths.root
        let standardizedURL = paths.url
        let directoryURL = standardizedURL.deletingLastPathComponent()
        try rejectReservedLockPath(standardizedURL, durableRootURL: standardizedRoot)
        return try withExclusiveAccess(through: standardizedRoot) {
            // Repair a directory-creation interruption after waiting for the
            // process lock; another writer may have created the ancestry.
            try ensureDurableDirectory(at: directoryURL, through: standardizedRoot)
            guard try managedFileExists(at: standardizedURL) else { return nil }
            return try quarantineWithExclusiveAccess(
                at: standardizedURL,
                prefix: prefix,
                directoryURL: directoryURL,
                durableRootURL: standardizedRoot
            )
        }
    }

    private func quarantineWithExclusiveAccess(
        at url: URL,
        prefix: String,
        directoryURL: URL,
        durableRootURL: URL
    ) throws -> URL? {
        let now = dateProvider()
        guard now.timeIntervalSinceReferenceDate.isFinite else {
            throw DurableLocalFileError.quarantineEntryMetadataUnavailable
        }
        let quarantineDirectory = directoryURL.appendingPathComponent(
            Self.quarantineDirectoryName,
            isDirectory: true
        )
        try ensureDurableDirectory(
            at: quarantineDirectory,
            through: durableRootURL
        )
        try excludeFromBackupIfRequested(
            quarantineDirectory,
            excludeFromBackup: true
        )

        let sourceByteCount = try fileByteCount(at: url)
        let canRetainCandidate = quarantinePolicy.maximumFileCount > 0
            && quarantinePolicy.maximumAge > 0
            && sourceByteCount <= quarantinePolicy.maximumTotalByteCount
        try pruneQuarantine(
            at: quarantineDirectory,
            now: now,
            reservingFileCount: canRetainCandidate ? 1 : 0,
            reservingByteCount: canRetainCandidate ? sourceByteCount : 0
        )

        guard canRetainCandidate else {
            // Moving a giant corrupt artifact would not consume additional
            // blocks, but retaining it would turn diagnostics into unbounded
            // storage. Durably remove the canonical file and report that no
            // diagnostic copy was kept.
            try removeWithExclusiveAccess(
                at: url.standardizedFileURL,
                durableRootURL: durableRootURL
            )
            return nil
        }
        let quarantineURL = quarantineDirectory.appendingPathComponent(
            prefix + UUID().uuidString + ".json"
        )
        var movedCanonicalFile = false
        do {
            // Attach metadata before rename publishes the diagnostic artifact.
            try protectIfSupported(url)
            try excludeFromBackupIfRequested(url, excludeFromBackup: true)
            try fileManager.moveItem(at: url, to: quarantineURL)
            movedCanonicalFile = true
            try fileManager.setAttributes(
                [.modificationDate: now],
                ofItemAtPath: quarantineURL.path
            )
            try protectIfSupported(quarantineURL)
            try excludeFromBackupIfRequested(
                quarantineURL,
                excludeFromBackup: true
            )
            try injectFault(.afterQuarantineMoveBeforeFileSync)
            try synchronizeFile(at: quarantineURL)
            try synchronizeDirectory(quarantineDirectory)
            try synchronizeDirectory(directoryURL)
            return quarantineURL
        } catch {
            if movedCanonicalFile {
                do {
                    try rollbackQuarantineMove(
                        from: quarantineURL,
                        to: url,
                        quarantineDirectory: quarantineDirectory,
                        sourceDirectory: directoryURL
                    )
                } catch {
                    throw DurableLocalFileError.quarantineRollbackFailed(
                        canonicalPath: url.path,
                        quarantinePath: quarantineURL.path
                    )
                }
            }
            throw error
        }
    }

}
