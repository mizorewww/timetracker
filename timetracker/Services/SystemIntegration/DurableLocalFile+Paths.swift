import Darwin
import Foundation

nonisolated extension DurableLocalFile {
    func ensureDurableDirectory(
        at directoryURL: URL,
        through durableRootURL: URL
    ) throws {
        let directoryChain = try directoryChain(
            from: directoryURL,
            through: durableRootURL
        )
        try rejectSymbolicLinks(in: directoryChain)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: durableRootURL.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw DurableLocalFileError.durableRootUnavailable
        }

        if fileManager.fileExists(atPath: directoryURL.path) == false {
            try injectFault(.beforeDirectoryCreation)
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try injectFault(.afterDirectoryCreationBeforeParentSync)
        }

        // Always replay leaf-to-root. A prior process may have completed mkdir
        // but died before its parent entry reached stable storage.
        for directory in directoryChain {
            try synchronizeDirectory(directory)
        }
    }

    func rejectSymbolicLink(at url: URL) throws {
        var metadata = stat()
        let result = url.path.withCString { path in
            Darwin.lstat(path, &metadata)
        }
        if result != 0 {
            let errorCode = errno
            if errorCode == ENOENT {
                return
            }
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
        guard (metadata.st_mode & S_IFMT) != S_IFLNK else {
            throw DurableLocalFileError.symbolicLinkNotAllowed
        }
    }

    func managedFileExists(at url: URL) throws -> Bool {
        var metadata = stat()
        let result = url.path.withCString { path in
            Darwin.lstat(path, &metadata)
        }
        if result != 0 {
            let errorCode = errno
            if errorCode == ENOENT {
                return false
            }
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
        guard (metadata.st_mode & S_IFMT) != S_IFLNK else {
            throw DurableLocalFileError.symbolicLinkNotAllowed
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw DurableLocalFileError.managedPathIsNotRegularFile
        }
        return true
    }

    func rejectReservedLockPath(_ url: URL, durableRootURL: URL) throws {
        let lockURL = durableRootURL
            .appendingPathComponent(Self.lockFileName)
            .standardizedFileURL
        guard url.standardizedFileURL.path != lockURL.path else {
            throw DurableLocalFileError.reservedLockPath
        }
    }

    func nearestExistingDirectory(atOrAbove directoryURL: URL) -> URL {
        var cursor = directoryURL
        while true {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: cursor.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                return cursor
            }
            guard cursor.pathComponents.count > 1 else { return cursor }
            cursor.deleteLastPathComponent()
        }
    }

    func canonicalDurableRoot(_ rootURL: URL) throws -> URL {
        let standardizedRoot = rootURL.standardizedFileURL
        // The durable root itself is managed and must never be an alias. The
        // caller's chosen boundary determines which ancestor aliases are trusted.
        try rejectSymbolicLink(at: standardizedRoot)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: standardizedRoot.path,
            isDirectory: &isDirectory
        ),
            isDirectory.boolValue
        else {
            throw DurableLocalFileError.durableRootUnavailable
        }
        let canonicalRoot = try CanonicalFileURL.resolvingExistingPath(
            standardizedRoot
        )
        try validateDirectoryPath(canonicalRoot)
        return canonicalRoot
    }

    private func directoryChain(from directoryURL: URL, through rootURL: URL) throws -> [URL] {
        let directoryComponents = directoryURL.pathComponents
        let rootComponents = rootURL.pathComponents
        guard directoryComponents.starts(with: rootComponents) else {
            throw DurableLocalFileError.durableRootIsNotAncestor
        }

        var chain: [URL] = []
        var cursor = directoryURL
        while true {
            chain.append(cursor)
            if cursor.path == rootURL.path {
                return chain
            }
            let parent = cursor.deletingLastPathComponent()
            // Foundation 27 can represent deleting the filesystem root as
            // `file:///../` instead of returning the root unchanged. The
            // component preflight bounds this walk to a proven ancestor.
            guard parent.pathComponents.count < cursor.pathComponents.count else {
                throw DurableLocalFileError.durableRootIsNotAncestor
            }
            cursor = parent
        }
    }

    private func rejectSymbolicLinks(in chain: [URL]) throws {
        for directory in chain.reversed() {
            try rejectSymbolicLink(at: directory)
        }
    }

    private func validateDirectoryPath(_ url: URL) throws {
        let descriptor = url.path.withCString { path in
            Darwin.open(
                path,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_CLOFORK | O_NOFOLLOW_ANY
            )
        }
        guard descriptor >= 0 else {
            let errorCode = errno
            if errorCode == ELOOP {
                throw DurableLocalFileError.symbolicLinkNotAllowed
            }
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
        Darwin.close(descriptor)
    }
}
