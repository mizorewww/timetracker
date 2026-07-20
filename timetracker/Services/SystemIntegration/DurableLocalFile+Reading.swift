import Darwin
import Foundation

nonisolated enum DurableLocalFileReadError: Error, Equatable, Sendable {
    case exceedsMaximumByteCount(
        actualByteCount: Int,
        maximumByteCount: Int
    )
}

nonisolated extension DurableLocalFile {
    func read(
        upTo maximumByteCount: Int,
        from url: URL,
        durableRootURL: URL
    ) throws -> Data? {
        precondition(maximumByteCount > 0)
        let paths = try canonicalManagedPaths(
            at: url,
            through: durableRootURL
        )
        try rejectReservedLockPath(
            paths.url,
            durableRootURL: paths.root
        )
        return try withExclusiveAccess(through: paths.root) {
            try readWithExclusiveAccess(
                upTo: maximumByteCount,
                from: paths.url
            )
        }
    }

    private func readWithExclusiveAccess(
        upTo maximumByteCount: Int,
        from url: URL
    ) throws -> Data? {
        try injectFault(.beforeManagedRead)
        let descriptor = url.path.withCString { path in
            Darwin.open(
                path,
                O_RDONLY | O_CLOEXEC | O_CLOFORK | O_NOFOLLOW_ANY
            )
        }
        guard descriptor >= 0 else {
            let errorCode = errno
            if errorCode == ENOENT { return nil }
            if errorCode == ELOOP {
                throw DurableLocalFileError.symbolicLinkNotAllowed
            }
            throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
        }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw DurableLocalFileError.managedPathIsNotRegularFile
        }
        let knownByteCount = metadata.st_size
        guard knownByteCount >= 0,
              knownByteCount <= Int64(maximumByteCount) else {
            throw DurableLocalFileReadError.exceedsMaximumByteCount(
                actualByteCount: Int(clamping: knownByteCount),
                maximumByteCount: maximumByteCount
            )
        }

        var data = Data()
        data.reserveCapacity(Int(knownByteCount))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let remaining = maximumByteCount - data.count
            let requestedByteCount = min(
                buffer.count,
                remaining == Int.max ? buffer.count : remaining + 1
            )
            let readByteCount = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(
                    descriptor,
                    bytes.baseAddress,
                    requestedByteCount
                )
            }
            if readByteCount < 0 {
                let errorCode = errno
                if errorCode == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errorCode) ?? .EIO)
            }
            if readByteCount == 0 { return data }
            data.append(contentsOf: buffer.prefix(readByteCount))
            guard data.count <= maximumByteCount else {
                throw DurableLocalFileReadError.exceedsMaximumByteCount(
                    actualByteCount: data.count,
                    maximumByteCount: maximumByteCount
                )
            }
        }
    }
}
