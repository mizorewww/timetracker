import Foundation
import SwiftData

final nonisolated class SwiftDataTaskRepository {
    let context: ModelContext
    let deviceID: String

    init(context: ModelContext, deviceID: String? = nil) {
        self.context = context
        self.deviceID = deviceID ?? DeviceIdentity.current
    }
}
