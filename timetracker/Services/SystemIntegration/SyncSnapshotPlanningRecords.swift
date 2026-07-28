import Foundation

nonisolated struct CountdownEventRecord:
    Codable,
    Equatable,
    SyncSnapshotRecord
{
    let id: UUID
    let title: String
    let date: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: CountdownEvent) {
        id = model.id
        title = model.title
        date = model.date
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}

nonisolated struct SyncedPreferenceRecord:
    Codable,
    Equatable,
    SyncSnapshotRecord
{
    let id: UUID
    let key: String
    let valueJSON: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    init(_ model: SyncedPreference) {
        id = model.id
        key = model.key
        valueJSON = model.valueJSON
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }
}
