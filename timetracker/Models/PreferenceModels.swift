import Foundation
import SwiftData

@Model
final class SyncedPreference {
    var id: UUID = UUID()
    var key: String = ""
    var valueJSON: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        key: String,
        valueJSON: String,
        deviceID: String
    ) {
        self.id = UUID()
        self.key = key
        self.valueJSON = valueJSON
        self.createdAt = Date()
        self.updatedAt = Date()
        self.deviceID = deviceID
        self.clientMutationID = UUID()
    }
}
