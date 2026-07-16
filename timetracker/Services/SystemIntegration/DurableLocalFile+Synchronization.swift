import Darwin
import Foundation

nonisolated extension DurableLocalFile {
    func protectIfSupported(_ url: URL) throws {
        #if os(iOS)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }

    func excludeFromBackupIfRequested(
        _ url: URL,
        excludeFromBackup: Bool
    ) throws {
        guard excludeFromBackup else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    func synchronizeFile(at url: URL) throws {
        let descriptor = url.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_CLOEXEC | O_CLOFORK | O_NOFOLLOW_ANY)
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        try synchronizeDescriptor(descriptor)
    }

    func synchronizeDirectory(_ url: URL) throws {
        if let directorySynchronizer {
            try directorySynchronizer(url)
            return
        }
        let descriptor = url.path.withCString { path in
            Darwin.open(
                path,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_CLOFORK | O_NOFOLLOW_ANY
            )
        }
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }
        try synchronizeDescriptor(descriptor)
    }

    func synchronizeDescriptor(_ descriptor: Int32) throws {
        while Darwin.fsync(descriptor) != 0 {
            let errorCode = errno
            if errorCode == EINTR { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
        while Darwin.fcntl(descriptor, F_FULLFSYNC) != 0 {
            let errorCode = errno
            if errorCode == EINTR { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
    }
}
