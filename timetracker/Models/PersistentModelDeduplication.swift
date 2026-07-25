import Foundation

protocol PersistentUUIDModel {
    var id: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
    var deviceID: String { get }
}

protocol SoftDeletablePersistentUUIDModel: AnyObject, PersistentUUIDModel {
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
    var deviceID: String { get set }
}

protocol ClientMutationTrackedModel: AnyObject {
    var clientMutationID: UUID { get set }
}

nonisolated enum PersistentLWWMutationDate {
    /// Returns the preferred wall-clock date when it already wins, otherwise
    /// advances by one CloudKit-safe millisecond. `Date` values are represented
    /// as Unix-epoch milliseconds by CloudKit, so `Double.nextUp` is too small
    /// to remain ordered after a sync round trip.
    static func strictlyDominating(
        preferred: Date,
        observed dates: Date...
    ) -> Date {
        strictlyDominating(preferred: preferred, observed: dates)
    }

    static func strictlyDominating(
        preferred: Date,
        observed dates: [Date]
    ) -> Date {
        guard let latest = dates.max() else { return preferred }
        // Two milliseconds leaves one full persisted tick even when converting
        // between Date's reference epoch and CloudKit's Unix-millisecond value
        // lands immediately below an integer boundary.
        return max(preferred, latest.addingTimeInterval(0.002))
    }
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

    /// Resolves last-write-wins before hiding tombstones. Filtering first can
    /// expose an older active duplicate after a newer deletion arrives via iCloud.
    func visibleDeduplicatedByID() -> [Element] {
        deduplicatedByID().filter { $0.deletedAt == nil }
    }
}

extension Sequence where Element: SoftDeletablePersistentUUIDModel {
    func latestByIDMarkingDuplicatesDeleted(now: Date, deviceID: String) -> [UUID: Element] {
        var indexesByID: [UUID: Int] = [:]
        var result: [Element] = []
        var duplicatedIDs = Set<UUID>()
        // Keep cleanup tombstones older than the canonical row under last-write-wins.
        let duplicateTombstoneDate = now.addingTimeInterval(-1)

        for element in self {
            if let existingIndex = indexesByID[element.id] {
                duplicatedIDs.insert(element.id)
                let existing = result[existingIndex]
                if element.isPreferred(over: existing) {
                    existing.markDuplicateDeleted(now: duplicateTombstoneDate, deviceID: deviceID)
                    result[existingIndex] = element
                } else {
                    element.markDuplicateDeleted(now: duplicateTombstoneDate, deviceID: deviceID)
                }
            } else {
                indexesByID[element.id] = result.count
                result.append(element)
            }
        }

        for winner in result where duplicatedIDs.contains(winner.id) {
            winner.updatedAt = Swift.max(winner.updatedAt, now)
            winner.deviceID = deviceID
            (winner as? ClientMutationTrackedModel)?.clientMutationID = UUID()
        }

        return result.reduce(into: [:]) { output, element in
            output[element.id] = element
        }
    }
}

private extension PersistentUUIDModel {
    func isPreferred(over other: Self) -> Bool {
        if updatedAt != other.updatedAt {
            return updatedAt > other.updatedAt
        }
        if (deletedAt == nil) != (other.deletedAt == nil) {
            return deletedAt != nil
        }
        if createdAt != other.createdAt {
            return createdAt > other.createdAt
        }
        if deviceID != other.deviceID {
            return deviceID > other.deviceID
        }
        if let mutation = self as? ClientMutationTrackedModel,
           let otherMutation = other as? ClientMutationTrackedModel,
           mutation.clientMutationID != otherMutation.clientMutationID
        {
            return mutation.clientMutationID.uuidString > otherMutation.clientMutationID.uuidString
        }
        if let segment = self as? TimeSegment,
           let otherSegment = other as? TimeSegment,
           segment.deterministicConflictKey != otherSegment.deterministicConflictKey
        {
            return segment.deterministicConflictKey > otherSegment.deterministicConflictKey
        }
        return false
    }
}

private extension TimeSegment {
    var deterministicConflictKey: String {
        [
            sessionID.uuidString,
            taskID.uuidString,
            String(startedAt.timeIntervalSinceReferenceDate),
            endedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "active",
            sourceRaw,
            deletedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "visible",
        ].joined(separator: "|")
    }
}

private extension SoftDeletablePersistentUUIDModel {
    func markDuplicateDeleted(now: Date, deviceID: String) {
        guard deletedAt == nil else { return }
        deletedAt = now
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
extension InboxCaptureReceipt: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension TaskRecurrenceRule: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension TaskRecurrenceOccurrence: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension TaskQuantityGoal: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
extension TaskQuantityEntry: SoftDeletablePersistentUUIDModel, ClientMutationTrackedModel {}
