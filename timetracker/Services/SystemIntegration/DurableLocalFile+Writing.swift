import Darwin
import Foundation

nonisolated extension DurableLocalFile {
    private static var temporaryWritePrefix: String {
        ".TimeTrackerWrite-"
    }

    private static var temporaryWriteSuffix: String {
        ".tmp"
    }

    func writeWithExclusiveAccess(
        _ data: Data,
        to url: URL,
        durableRootURL: URL,
        excludeFromBackup: Bool
    ) throws {
        let directoryURL = url.deletingLastPathComponent()
        try ensureDurableDirectory(at: directoryURL, through: durableRootURL)
        try rejectReservedLockPath(url, durableRootURL: durableRootURL)
        _ = try managedFileExists(at: url)
        try removeStaleTemporaryFiles(in: directoryURL)

        let temporaryURL = directoryURL.appendingPathComponent(
            Self.temporaryWritePrefix + UUID().uuidString + Self.temporaryWriteSuffix
        )
        let descriptor = temporaryURL.path.withCString { path in
            Darwin.open(
                path,
                O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_CLOFORK | O_NOFOLLOW_ANY,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var descriptorIsOpen = true
        var published = false
        defer {
            if descriptorIsOpen {
                Darwin.close(descriptor)
            }
            if published == false {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        try writeAll(data, to: descriptor)
        try protectIfSupported(temporaryURL)
        try excludeFromBackupIfRequested(
            temporaryURL,
            excludeFromBackup: excludeFromBackup
        )
        try injectFault(.afterAtomicWriteBeforeFileSync)
        try synchronizeDescriptor(descriptor)
        guard Darwin.close(descriptor) == 0 else {
            descriptorIsOpen = false
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        descriptorIsOpen = false

        let renameResult = temporaryURL.path.withCString { temporaryPath in
            url.path.withCString { destinationPath in
                Darwin.rename(temporaryPath, destinationPath)
            }
        }
        guard renameResult == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        published = true
        try injectFault(.afterFileSyncBeforeDirectorySync)
        try synchronizeDirectory(directoryURL)
    }

    func removeWithExclusiveAccess(at url: URL, durableRootURL: URL) throws {
        let directoryURL = url.deletingLastPathComponent()
        try ensureDurableDirectory(at: directoryURL, through: durableRootURL)
        try rejectReservedLockPath(url, durableRootURL: durableRootURL)
        // Replay the directory ancestry even when the file is already absent:
        // a previous process may have unlinked it and died before fsync.
        guard try managedFileExists(at: url) else { return }
        let unlinkResult = url.path.withCString(Darwin.unlink)
        guard unlinkResult == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try injectFault(.afterRemovalBeforeDirectorySync)
        try synchronizeDirectory(directoryURL)
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset < rawBuffer.count {
                guard let baseAddress = rawBuffer.baseAddress else { break }
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written < 0 {
                    let errorCode = errno
                    if errorCode == EINTR {
                        continue
                    }
                    throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
                }
                guard written > 0 else { throw POSIXError(.EIO) }
                offset += written
            }
        }
    }

    private func removeStaleTemporaryFiles(in directoryURL: URL) throws {
        let candidates = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix(Self.temporaryWritePrefix)
                && $0.lastPathComponent.hasSuffix(Self.temporaryWriteSuffix)
        }
        var removedFile = false
        for candidate in candidates {
            var metadata = stat()
            let status = candidate.path.withCString { Darwin.lstat($0, &metadata) }
            if status != 0 {
                let errorCode = errno
                if errorCode == ENOENT {
                    continue
                }
                throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
            }
            let fileType = metadata.st_mode & S_IFMT
            guard fileType == S_IFREG || fileType == S_IFLNK else { continue }
            let result = candidate.path.withCString(Darwin.unlink)
            guard result == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            removedFile = true
        }
        if removedFile {
            try synchronizeDirectory(directoryURL)
        }
    }
}
