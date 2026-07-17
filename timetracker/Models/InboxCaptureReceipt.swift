import Foundation
import SwiftData

/// Durable acknowledgement for an Inbox capture whose caller supplied a
/// stable external command key. It is intentionally separate from `InboxItem`:
/// user-facing item identity must not become part of an integration protocol.
@Model
final class InboxCaptureReceipt {
    var id: UUID = UUID()
    var commandKey: String = ""
    var payloadFingerprint: String = ""
    var inboxItemID: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        commandKey: String,
        payloadFingerprint: String,
        inboxItemID: UUID,
        createdAt: Date = Date(),
        deviceID: String
    ) {
        id = UUID()
        self.commandKey = commandKey
        self.payloadFingerprint = payloadFingerprint
        self.inboxItemID = inboxItemID
        self.createdAt = createdAt
        updatedAt = createdAt
        self.deviceID = deviceID
        clientMutationID = UUID()
    }
}
