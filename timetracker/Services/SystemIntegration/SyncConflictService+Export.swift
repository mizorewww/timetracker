import Foundation
import SwiftData

extension SyncConflictService {
    func exportCloudSyncedData(context: ModelContext, exportedAt: Date = Date()) throws -> String {
        try withLockedFreshStoreContext(context: context) { lockedContext in
            let export = try SyncDataExport(
                exportedAt: exportedAt,
                appVersion: AppBuildInfo.versionSummary,
                data: SyncDataSnapshot.capture(context: lockedContext)
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(export)
            return String(data: data, encoding: .utf8) ?? "{}"
        }
    }
}
