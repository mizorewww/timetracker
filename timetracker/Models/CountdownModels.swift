import Foundation
import SwiftData

@Model
final class CountdownEvent {
    var id: UUID = UUID()
    var title: String = ""
    var date: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var deviceID: String = ""
    var clientMutationID: UUID = UUID()

    init(
        title: String,
        date: Date,
        deviceID: String
    ) {
        id = UUID()
        self.title = title
        self.date = date
        createdAt = Date()
        updatedAt = Date()
        self.deviceID = deviceID
        clientMutationID = UUID()
    }
}
