import Foundation
import SwiftData

@MainActor
final class SwiftDataTaskRepository: TaskRepository {
    let context: ModelContext
    let deviceID: String

    init(context: ModelContext, deviceID: String? = nil) {
        self.context = context
        self.deviceID = deviceID ?? DeviceIdentity.current
    }
}
