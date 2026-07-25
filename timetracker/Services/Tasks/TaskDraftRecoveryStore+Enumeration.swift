import Foundation

nonisolated struct TaskDraftRecoveryRecord:
    Identifiable,
    Equatable,
    Sendable
{
    let sourceTaskID: UUID
    let savedAt: Date
    let draft: TaskEditorDraft

    var id: UUID {
        sourceTaskID
    }
}

nonisolated extension TaskDraftRecoveryStore {
    /// Returns every valid recovery draft without requiring its source task to
    /// still exist. Invalid entries are removed only after bounded decoding
    /// confirms that they cannot be recovered.
    func recoverableRecords() throws -> [TaskDraftRecoveryRecord] {
        let locations = try resolvedLocations()
        return try localFile.withExclusiveAccess(
            through: locations.durableRoot
        ) {
            let candidates = try localFile.managedDirectoryContents(
                at: locations.directory,
                durableRootURL: locations.durableRoot
            ).filter { $0.pathExtension == "json" }
            var records: [TaskDraftRecoveryRecord] = []

            for url in candidates {
                guard let envelope = try readEnvelope(
                    at: url,
                    locations: locations
                ) else { continue }
                let isValid =
                    envelope.schemaVersion == Self.currentSchemaVersion &&
                    envelope.draft.taskID == envelope.sourceTaskID &&
                    envelope.draft.baseline != nil &&
                    fileName(for: envelope.sourceTaskID) ==
                    url.lastPathComponent &&
                    isExpired(envelope.savedAt) == false
                guard isValid else {
                    try removeFile(at: url, locations: locations)
                    continue
                }
                records.append(
                    TaskDraftRecoveryRecord(
                        sourceTaskID: envelope.sourceTaskID,
                        savedAt: envelope.savedAt,
                        draft: envelope.draft
                    )
                )
            }

            return records.sorted {
                if $0.savedAt != $1.savedAt {
                    return $0.savedAt > $1.savedAt
                }
                return $0.sourceTaskID.uuidString <
                    $1.sourceTaskID.uuidString
            }
        }
    }
}
