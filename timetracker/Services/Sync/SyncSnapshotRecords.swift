import Foundation

nonisolated protocol SyncSnapshotRecord: Sendable {
    var id: UUID { get }
}

nonisolated extension Array where Element: SyncSnapshotRecord {
    func sortedByID() -> [Element] {
        sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

nonisolated extension Array where Element: SyncSnapshotRecord & Equatable {
    mutating func applyChanges(from baseline: [Element], to updated: [Element]) {
        var resultByID = recordsByID()
        let baselineByID = baseline.recordsByID()
        let updatedByID = updated.recordsByID()
        let comparedIDs = Set(baselineByID.keys).union(updatedByID.keys)

        for id in comparedIDs where baselineByID[id] != updatedByID[id] {
            if let record = updatedByID[id] {
                resultByID[id] = record
            } else {
                resultByID.removeValue(forKey: id)
            }
        }
        self = Array(resultByID.values).sortedByID()
    }

    /// Historical state files may predate model-level deduplication. Taking the
    /// last encoded record keeps migration deterministic instead of trapping on
    /// `Dictionary(uniqueKeysWithValues:)` when an identifier is repeated.
    private func recordsByID() -> [UUID: Element] {
        reduce(into: [:]) { records, record in
            records[record.id] = record
        }
    }
}

nonisolated struct TaskRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let title: String
    let kindRaw: String
    let parentID: UUID?
    let sortOrder: Double
    let path: String
    let depth: Int
    let statusRaw: String
    let colorHex: String?
    let iconName: String?
    let estimatedSeconds: Int?
    let dueAt: Date?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let archivedAt: Date?
    let deletedAt: Date?

    init(_ model: TaskNode) {
        id = model.id
        title = model.title
        kindRaw = model.kindRaw
        parentID = model.parentID
        sortOrder = model.sortOrder
        path = model.path
        depth = model.depth
        statusRaw = model.statusRaw
        colorHex = model.colorHex
        iconName = model.iconName
        estimatedSeconds = model.estimatedSeconds
        dueAt = model.dueAt
        notes = model.notes
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        archivedAt = model.archivedAt
        deletedAt = model.deletedAt
    }
}

nonisolated struct TaskCategoryRecord: Codable, Equatable, SyncSnapshotRecord {
    let id: UUID
    let title: String
    let colorHex: String?
    let iconName: String?
    let includesInForecast: Bool
    let sortOrder: Double
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TaskCategory) {
        id = model.id
        title = model.title
        colorHex = model.colorHex
        iconName = model.iconName
        includesInForecast = model.includesInForecast
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

nonisolated struct TaskCategoryAssignmentRecord:
    Codable,
    Equatable,
    SyncSnapshotRecord
{
    let id: UUID
    let taskID: UUID
    let categoryID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: TaskCategoryAssignment) {
        id = model.id
        taskID = model.taskID
        categoryID = model.categoryID
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}
