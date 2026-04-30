import Foundation
import SwiftData

@MainActor
struct PreferenceCommandHandler {
    func set(key: AppPreferenceKey, valueJSON: String, context: ModelContext, now: Date = Date()) throws {
        let rawKey = key.rawValue
        let descriptor = FetchDescriptor<SyncedPreference>(
            predicate: #Predicate { $0.key == rawKey && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let existing = try context.fetch(descriptor)
        let target = existing.first ?? SyncedPreference(
            key: key.rawValue,
            valueJSON: valueJSON,
            deviceID: DeviceIdentity.current
        )
        if existing.isEmpty {
            context.insert(target)
        }
        target.valueJSON = valueJSON
        target.updatedAt = now
        target.deviceID = DeviceIdentity.current
        target.clientMutationID = UUID()
        for duplicate in existing.dropFirst() {
            duplicate.deletedAt = now
            duplicate.updatedAt = now
            duplicate.clientMutationID = UUID()
        }
        try context.save()
    }
}
