import Darwin
import Foundation

nonisolated extension DurableLocalFile {
    func pruneQuarantine(
        at directoryURL: URL,
        now: Date,
        reservingFileCount: Int,
        reservingByteCount: Int64
    ) throws {
        try injectFault(.beforeQuarantinePruning)
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: []
        )
        var entries: [QuarantineEntry] = []
        var urlsToRemove: [URL] = []
        let oldestAllowedDate = now.addingTimeInterval(-quarantinePolicy.maximumAge)
        let newestAllowedDate = now.addingTimeInterval(quarantinePolicy.maximumAge)

        for url in urls {
            let values = try url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ])
            guard values.isSymbolicLink != true, values.isRegularFile == true else {
                urlsToRemove.append(url)
                continue
            }
            guard let byteCount = values.fileSize.map(Int64.init),
                  byteCount >= 0,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt.timeIntervalSinceReferenceDate.isFinite
            else {
                throw DurableLocalFileError.quarantineEntryMetadataUnavailable
            }
            if modifiedAt <= oldestAllowedDate || modifiedAt > newestAllowedDate {
                urlsToRemove.append(url)
            } else {
                entries.append(
                    QuarantineEntry(
                        url: url,
                        byteCount: byteCount,
                        modifiedAt: modifiedAt
                    )
                )
            }
        }

        entries.sort {
            if $0.modifiedAt != $1.modifiedAt {
                return $0.modifiedAt > $1.modifiedAt
            }
            return $0.url.lastPathComponent > $1.url.lastPathComponent
        }
        var retainedFileCount = reservingFileCount
        var retainedByteCount = reservingByteCount
        for entry in entries {
            let (nextByteCount, overflow) = retainedByteCount.addingReportingOverflow(
                entry.byteCount
            )
            let fits = overflow == false
                && retainedFileCount < quarantinePolicy.maximumFileCount
                && nextByteCount <= quarantinePolicy.maximumTotalByteCount
            if fits {
                retainedFileCount += 1
                retainedByteCount = nextByteCount
            } else {
                urlsToRemove.append(entry.url)
            }
        }

        guard urlsToRemove.isEmpty == false else { return }
        for url in urlsToRemove {
            let result = url.path.withCString(Darwin.unlink)
            guard result == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
        try injectFault(.afterQuarantinePruningBeforeDirectorySync)
        try synchronizeDirectory(directoryURL)
    }

    func fileByteCount(at url: URL) throws -> Int64 {
        guard try managedFileExists(at: url) else {
            throw DurableLocalFileError.quarantineEntryMetadataUnavailable
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let number = attributes[.size] as? NSNumber else {
            throw DurableLocalFileError.quarantineEntryMetadataUnavailable
        }
        let byteCount = number.int64Value
        guard byteCount >= 0 else {
            throw DurableLocalFileError.quarantineEntryMetadataUnavailable
        }
        return byteCount
    }

    func rollbackQuarantineMove(
        from quarantineURL: URL,
        to sourceURL: URL,
        quarantineDirectory: URL,
        sourceDirectory: URL
    ) throws {
        guard try managedFileExists(at: quarantineURL),
              try managedFileExists(at: sourceURL) == false
        else {
            throw DurableLocalFileError.quarantineRollbackFailed(
                canonicalPath: sourceURL.path,
                quarantinePath: quarantineURL.path
            )
        }
        try fileManager.moveItem(at: quarantineURL, to: sourceURL)
        try synchronizeFile(at: sourceURL)
        try synchronizeDirectory(quarantineDirectory)
        try synchronizeDirectory(sourceDirectory)
    }
}

private struct QuarantineEntry {
    let url: URL
    let byteCount: Int64
    let modifiedAt: Date
}
