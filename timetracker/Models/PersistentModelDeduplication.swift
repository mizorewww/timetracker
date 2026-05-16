import Foundation

protocol PersistentUUIDModel {
    var id: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
}

protocol SoftDeletablePersistentUUIDModel: AnyObject, PersistentUUIDModel {
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var deviceID: String { get set }
}

protocol ClientMutationTrackedModel: AnyObject {
    var clientMutationID: UUID { get set }
}

extension Sequence where Element: PersistentUUIDModel {
    func deduplicatedByID() -> [Element] {
        var indexesByID: [UUID: Int] = [:]
        var result: [Element] = []

        for element in self {
            if let existingIndex = indexesByID[element.id] {
                if element.isPreferred(over: result[existingIndex]) {
                    result[existingIndex] = element
                }
            } else {
                indexesByID[element.id] = result.count
                result.append(element)
            }
        }

        return result
    }

    func latestByID() -> [UUID: Element] {
        deduplicatedByID().reduce(into: [:]) { result, element in
            result[element.id] = element
        }
    }
}

extension Sequence where Element: SoftDeletablePersistentUUIDModel {
    func latestByIDMarkingDuplicatesDeleted(now: Date, deviceID: String) -> [UUID: Element] {
        var indexesByID: [UUID: Int] = [:]
        var result: [Element] = []

        for element in self {
            if let existingIndex = indexesByID[element.id] {
                let existing = result[existingIndex]
                if element.isPreferred(over: existing) {
                    existing.markDuplicateDeleted(now: now, deviceID: deviceID)
                    result[existingIndex] = element
                } else {
                    element.markDuplicateDeleted(now: now, deviceID: deviceID)
                }
            } else {
                indexesByID[element.id] = result.count
                result.append(element)
            }
        }

        return result.reduce(into: [:]) { output, element in
            output[element.id] = element
        }
    }
}

private extension PersistentUUIDModel {
    func isPreferred(over other: Self) -> Bool {
        if (deletedAt == nil) != (other.deletedAt == nil) {
            return deletedAt == nil
        }
        if updatedAt != other.updatedAt {
            return updatedAt > other.updatedAt
        }
        return createdAt > other.createdAt
    }
}

private extension SoftDeletablePersistentUUIDModel {
    func markDuplicateDeleted(now: Date, deviceID: String) {
        deletedAt = deletedAt ?? now
        updatedAt = now
        self.deviceID = deviceID
        (self as? ClientMutationTrackedModel)?.clientMutationID = UUID()
    }
}

extension TaskNode: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension TaskCategory: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension TaskCategoryAssignment: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension TimeSession: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension TimeSegment: SoftDeletablePersistentUUIDModel {}
extension PomodoroRun: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension CountdownEvent: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension SyncedPreference: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension ChecklistItem: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension ChecklistItemVisual: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension InboxItem: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension InboxSuggestion: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
