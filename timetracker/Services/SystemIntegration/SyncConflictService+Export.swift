import Foundation
import SwiftData

extension SyncConflictService {
    func exportCloudSyncedData(context: ModelContext, exportedAt: Date = Date()) throws -> String {
        let export = SyncDataExport(
            exportedAt: exportedAt,
            appVersion: AppBuildInfo.versionSummary,
            data: try SyncDataSnapshot.capture(context: context)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(export)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
