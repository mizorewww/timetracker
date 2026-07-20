import Darwin
import Foundation

nonisolated extension DurableLocalFile {
    func managedDirectoryContents(
        at directoryURL: URL,
        durableRootURL: URL
    ) throws -> [URL] {
        let paths = try canonicalManagedPaths(
            at: directoryURL,
            through: durableRootURL
        )
        return try withExclusiveAccess(through: paths.root) {
            try directoryContentsWithExclusiveAccess(at: paths.url)
        }
    }

    private func directoryContentsWithExclusiveAccess(
        at directoryURL: URL
    ) throws -> [URL] {
        let descriptor = directoryURL.path.withCString { path in
            Darwin.open(
                path,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_CLOFORK | O_NOFOLLOW_ANY
            )
        }
        guard descriptor >= 0 else {
            let errorCode = errno
            if errorCode == ENOENT { return [] }
            if errorCode == ELOOP {
                throw DurableLocalFileError.symbolicLinkNotAllowed
            }
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
        guard let stream = Darwin.fdopendir(descriptor) else {
            let errorCode = errno
            Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
        defer { Darwin.closedir(stream) }

        var contents: [URL] = []
        while true {
            errno = 0
            guard let entry = Darwin.readdir(stream) else {
                guard errno == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                return contents
            }
            var nameBuffer = entry.pointee.d_name
            let nameCapacity = MemoryLayout.size(ofValue: nameBuffer)
            let name = withUnsafePointer(to: &nameBuffer) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: nameCapacity
                ) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }
            contents.append(directoryURL.appendingPathComponent(name))
        }
    }
}
