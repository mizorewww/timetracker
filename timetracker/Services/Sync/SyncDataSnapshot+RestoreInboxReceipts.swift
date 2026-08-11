import Foundation
import SwiftData

@MainActor
extension SyncDataSnapshot {
    func restoreInboxCaptureReceipts(
        context: ModelContext,
        now: Date,
        deviceID: String
    ) throws {
        // A V10-or-earlier recovery snapshot has no receipt table. It cannot
        // authoritatively delete V11 receipts already present in this store.
        guard let records = inboxCaptureReceipts else { return }
        var existing = try context.fetch(FetchDescriptor<InboxCaptureReceipt>())
            .latestByIDMarkingDuplicatesDeleted(now: now, deviceID: deviceID)
        let snapshotIDs = Set(records.map(\.id))
        let supersededAt = now.addingTimeInterval(-1)

        for receipt in existing.values where !snapshotIDs.contains(receipt.id) {
            receipt.deletedAt = supersededAt
            receipt.updatedAt = supersededAt
            receipt.deviceID = deviceID
            receipt.clientMutationID = UUID()
        }

        for record in records {
            let model = existing[record.id] ?? InboxCaptureReceipt(
                commandKey: record.commandKey,
                payloadFingerprint: record.payloadFingerprint,
                inboxItemID: record.inboxItemID,
                createdAt: record.createdAt,
                deviceID: deviceID
            )
            if existing[record.id] == nil {
                context.insert(model)
                existing[record.id] = model
            }
            model.id = record.id
            model.commandKey = record.commandKey
            model.payloadFingerprint = record.payloadFingerprint
            model.inboxItemID = record.inboxItemID
            model.createdAt = record.createdAt
            model.updatedAt = record.updatedAt
            model.deletedAt = record.deletedAt
            model.deviceID = deviceID
            model.clientMutationID = record.id
        }
    }
}
