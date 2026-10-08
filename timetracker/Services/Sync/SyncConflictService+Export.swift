import Foundation
import SwiftData

extension SyncConflictService {
    func exportCloudSyncedData(
        context: ModelContext,
        exportedAt: Date = Date()
    ) throws -> String {
        try withLockedFreshStoreContext(context: context) { lockedContext in
            let export = try SyncDataExport(
                exportedAt: exportedAt,
                appVersion: AppBuildInfo.versionSummary,
                data: SyncDataSnapshot.capture(context: lockedContext)
            )
            return try encodedExport(export)
        }
    }

    private func encodedExport<T: Encodable>(
        _ export: T
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try String(
            decoding: encoder.encode(export),
            as: UTF8.self
        )
    }
}
